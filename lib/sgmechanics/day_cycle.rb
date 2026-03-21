# frozen_string_literal: true

require 'date'

module Sgmechanics
  # 任意のリセット時刻を基準とした「1日」を管理するクラス。
  #
  # カレンダー上の0時ではなく、任意の時・分・秒をリセット時刻として設定できます。
  # JST 5:00 リセットや 23:30 リセットなど、ソーシャルゲームでよくある
  # 日付境界の計算に使用します。
  #
  # @example JST 5:00 リセット
  #   dc = Sgmechanics::DayCycle.new(reset_hour: 5, utc_offset: "+09:00")
  #   dc.game_day(Time.new(2024, 1, 10, 4, 59, 59, "+09:00")) # => #<Date: 2024-01-09>
  #   dc.game_day(Time.new(2024, 1, 10, 5,  0,  0, "+09:00")) # => #<Date: 2024-01-10>
  class DayCycle
    # @param reset_hour [Integer] リセット時刻の「時」（0〜23）
    # @param reset_minute [Integer] リセット時刻の「分」（0〜59）
    # @param reset_second [Integer] リセット時刻の「秒」（0〜59）
    # @param utc_offset [String] タイムゾーンの UTC オフセット（例: "+09:00"）
    def initialize(reset_hour: 0, reset_minute: 0, reset_second: 0, utc_offset: '+00:00')
      @reset_hour   = reset_hour
      @reset_minute = reset_minute
      @reset_second = reset_second
      @utc_offset   = utc_offset
      @offset_seconds = parse_offset(utc_offset)
    end

    # 指定した時刻が属するゲーム内日付（Date）を返す。
    #
    # リセット時刻より前なら前日扱いになる。
    #
    # @param time [Time] 判定する時刻
    # @return [Date]
    def game_day(time)
      local = time.getlocal(@offset_seconds)
      reset_today = reset_time_on(local.to_date, local)
      if local >= reset_today
        local.to_date
      else
        local.to_date - 1
      end
    end

    # 直近のリセット時刻を返す。
    #
    # @param time [Time] 基準時刻
    # @return [Time]
    def last_reset(time)
      local = time.getlocal(@offset_seconds)
      reset_today = reset_time_on(local.to_date, local)
      if local >= reset_today
        reset_today
      else
        reset_time_on(local.to_date - 1, local)
      end
    end

    # 次回のリセット時刻を返す。
    #
    # @param time [Time] 基準時刻
    # @return [Time]
    def next_reset(time)
      local = time.getlocal(@offset_seconds)
      reset_today = reset_time_on(local.to_date, local)
      if local >= reset_today
        reset_time_on(local.to_date + 1, local)
      else
        reset_today
      end
    end

    # 次回リセットまでの秒数を返す。
    #
    # @param time [Time] 基準時刻
    # @return [Float]
    def seconds_until_next_reset(time)
      next_reset(time) - time
    end

    # from〜to の間にリセット境界が存在するかを返す。
    #
    # デイリーボーナスの取得判定などに使用する。
    #
    # @param from [Time] 区間の開始時刻
    # @param to [Time] 区間の終了時刻
    # @return [Boolean]
    #
    # @example デイリーボーナス付与判定
    #   if dc.reset_occurred_between?(from: last_login_at, to: Time.now)
    #     grant_daily_bonus!
    #   end
    def reset_occurred_between?(from:, to:)
      last_reset(to) > from
    end

    private

    def parse_offset(utc_offset)
      sign = utc_offset.start_with?('-') ? -1 : 1
      parts = utc_offset.delete('+-').split(':')
      sign * ((parts[0].to_i * 3600) + (parts[1].to_i * 60))
    end

    def reset_time_on(date, reference_local_time)
      Time.new(date.year, date.month, date.day,
               @reset_hour, @reset_minute, @reset_second,
               reference_local_time.utc_offset)
    end
  end
end
