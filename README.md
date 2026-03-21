# sgmechanics

ソーシャルゲームでよく使われるゲームメカニクスを実装した Ruby ライブラリです。

- **Stamina** — スタミナ（AP/BP）の回復タイマー管理
- **DayCycle** — ゲーム内1日のリセット時刻管理
- **Gacha** — 重み付き抽選・天井・レートアップ

## インストール

```ruby
# Gemfile
gem "sgmechanics"
```

```bash
bundle install
```

## Stamina

スタミナの現在値・回復完了時刻を管理するクラスです。「今の時刻」を外から渡す設計なので、テストが容易です。

```ruby
require "sgmechanics"

now              = Time.now.to_i   # Unix タイムスタンプ (Integer/Float)
max_stamina      = 120
seconds_per_stamina = 300          # 5分で1回復

stamina = Sgmechanics::Stamina.new(
  max_stamina,
  seconds_per_stamina,
  completion_time,    # 回復が完了する時刻 (Unix タイムスタンプ)
  overflowed_stamina, # 最大値を超えた分 (通常は 0)
  now
)

stamina.value            # => 現在のスタミナ値 (overflow 込み)
stamina.full?            # => 満タンか
stamina.seconds_for_max  # => 満タンになるまでの秒数
stamina.seconds_for_next # => 次の1回復までの秒数

stamina.increase(30)     # スタミナを増やす (最大超過分は overflow へ)
stamina.decrease(10)     # スタミナを消費する (不足時は DecreaseError)
stamina.to_fill          # 即座に満タンにする
stamina.to_empty         # 即座に空にする
```

### 永続化のパターン

```ruby
# 保存するのは completion_time と overflowed_stamina の2値だけ
record = { completion_time: stamina.completion_time,
           overflowed_stamina: stamina.overflowed_stamina }

# 復元
stamina = Sgmechanics::Stamina.new(
  max_stamina, seconds_per_stamina,
  record[:completion_time], record[:overflowed_stamina],
  Time.now.to_i
)
```

## DayCycle

ゲーム内日付のリセット時刻を管理するクラスです。JST 5時リセットなど、カレンダー上の0時とは異なるリセットに対応します。

```ruby
# JST 5:00 リセット
lc = Sgmechanics::DayCycle.new(reset_hour: 5, utc_offset: "+09:00")

now = Time.now

lc.game_day(now)                        # => Date (ゲーム内の今日)
lc.last_reset(now)                      # => Time (直近のリセット時刻)
lc.next_reset(now)                      # => Time (次回リセット時刻)
lc.seconds_until_next_reset(now)        # => Float (次のリセットまでの秒数)
lc.reset_occurred_between?(from:, to:)  # => Boolean (ログイン間にリセットが挟まったか)
```

### 動作例

```ruby
lc = Sgmechanics::DayCycle.new(reset_hour: 5, utc_offset: "+09:00")

# JST 2024-01-10 04:59:59 → ゲーム内はまだ 1月9日
lc.game_day(Time.new(2024, 1, 10, 4, 59, 59, "+09:00"))
# => #<Date: 2024-01-09>

# JST 2024-01-10 05:00:00 → ゲーム内は 1月10日
lc.game_day(Time.new(2024, 1, 10, 5, 0, 0, "+09:00"))
# => #<Date: 2024-01-10>
```

### デイリーボーナス取得済み判定

```ruby
last_login = Time.new(2024, 1, 10, 4, 0, 0, "+09:00")
now        = Time.new(2024, 1, 10, 6, 0, 0, "+09:00")

# 前回ログインと今回の間に 5:00 リセットが挟まっている → デイリーボーナス付与
if lc.reset_occurred_between?(from: last_login, to: now)
  grant_daily_bonus!
end
```

### カスタムリセット時刻

```ruby
# 23:30:00 リセット、UTC
lc = Sgmechanics::DayCycle.new(
  reset_hour: 23, reset_minute: 30, reset_second: 0,
  utc_offset: "+00:00"
)
```

## Gacha

重み付き抽選・天井（ピティ）・レートアップをサポートするガチャエンジンです。設定オブジェクト (`Gacha`) と状態オブジェクト (`GachaSession`) を分離しており、状態だけ DB に保存できます。

### アイテム定義

```ruby
Item = Sgmechanics::Gacha::Item  # 便宜上

pool = [
  Item.new(id: :sword_common, weight: 70, rare: false),
  Item.new(id: :sword_rare,   weight: 20, rare: false),
  Item.new(id: :sword_sr,     weight:  8, rare: true),
  Item.new(id: :sword_ssr,    weight:  2, rare: true),
]
```

`weight` の合計に対する比率で当選確率が決まります。上記では SSR は 2% です。

### セッションなし抽選

天井やレートアップが不要な場合はシンプルに使えます。

```ruby
gacha = Sgmechanics::Gacha.new(item_pool: pool)

gacha.pull                   # => Item (1回)
gacha.multi_pull(count: 10)  # => Array<Item> (10連)
```

### セッションあり抽選（天井・レートアップ）

```ruby
gacha = Sgmechanics::Gacha.new(
  item_pool:          pool,
  pity_count:         90,             # 90連で rare 確定
  rate_up_items:      [pool[3]],      # レートアップ対象 (sword_ssr)
  rate_up_multiplier: 2               # レートアップ時は weight を2倍
)

# 新規セッション（ゲーム開始時 or DB に保存されたデータがないとき）
session = gacha.new_session

item = session.pull             # => Item (天井カウンター自動更新)
items = session.multi_pull(count: 10)

session.pity_counter            # => Integer (現在の天井カウンター)
session.rate_up                 # => Boolean (レートアップ中か)
```

### セッションの永続化

```ruby
# DB に保存
record = session.to_h
# => { pity_counter: 42, rate_up: false }

# DB から復元
session = Sgmechanics::GachaSession.from_h(gacha: gacha, state: record)
```

### 天井アルゴリズム

1. `pity_counter + 1 >= pity_count` → rare アイテムのみから抽選 → カウンター 0 リセット
2. 通常抽選で rare が出た場合もカウンター 0 リセット
3. 非 rare が出た場合はカウンターをインクリメント

## 開発

```bash
bundle install
bundle exec rspec        # テスト実行
bundle exec rake build   # gem ビルド
bin/console              # irb でインタラクティブに試す
```

## ライセンス

[MIT License](LICENSE)
