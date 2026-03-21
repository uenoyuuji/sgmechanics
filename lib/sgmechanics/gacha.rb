# frozen_string_literal: true

module Sgmechanics
  # 重み付き抽選・天井（ピティ）・レートアップをサポートするガチャエンジン。
  #
  # 設定オブジェクト ({Gacha}) とセッション状態 ({GachaSession}) を分離しており、
  # セッション状態だけ DB に永続化できます。
  #
  # @example 基本的な使い方
  #   pool = [
  #     Sgmechanics::Gacha::Item.new(id: :common, weight: 90, rare: false),
  #     Sgmechanics::Gacha::Item.new(id: :rare,   weight: 10, rare: true),
  #   ]
  #   gacha = Sgmechanics::Gacha.new(item_pool: pool, pity_count: 90)
  #   session = gacha.new_session
  #   item = session.pull
  class Gacha
    # ガチャのアイテムを表す不変（frozen）の値オブジェクト。
    #
    # @!attribute [r] id
    #   @return [Object] アイテムの識別子
    # @!attribute [r] weight
    #   @return [Integer] 抽選の重み
    # @!attribute [r] rare
    #   @return [Boolean] レアアイテムかどうか（天井の対象）
    Item = Struct.new(:id, :weight, :rare, keyword_init: true) do
      def initialize(...)
        super
        freeze
      end
    end

    # @param item_pool [Array<Item>] 抽選対象のアイテム一覧
    # @param pity_count [Integer] 天井までの抽選回数（0 で天井なし）
    # @param rate_up_items [Array<Item>] レートアップ対象のアイテム
    # @param rate_up_multiplier [Numeric] レートアップ時の weight 倍率
    def initialize(item_pool:, pity_count: 0, rate_up_items: [], rate_up_multiplier: 2)
      @item_pool          = item_pool
      @pity_count         = pity_count
      @rate_up_items      = rate_up_items
      @rate_up_multiplier = rate_up_multiplier
    end

    # セッションなしで単発抽選を行う。天井・レートアップは考慮しない。
    #
    # @param random [Random] 乱数オブジェクト
    # @return [Item]
    def pull(random: Random)
      weighted_sample(@item_pool, random)
    end

    # セッションなしで複数連抽選を行う。天井・レートアップは考慮しない。
    #
    # @param count [Integer] 抽選回数
    # @param random [Random] 乱数オブジェクト
    # @return [Array<Item>]
    def multi_pull(count:, random: Random)
      Array.new(count) { pull(random: random) }
    end

    # 天井・レートアップを管理するセッションを生成する。
    #
    # @param pity_counter [Integer] 現在の天井カウンター
    # @param rate_up [Boolean] レートアップ中かどうか
    # @param random [Random] 乱数オブジェクト
    # @return [GachaSession]
    def new_session(pity_counter: 0, rate_up: false, random: Random)
      GachaSession.new(gacha: self, pity_counter: pity_counter, rate_up: rate_up, random: random)
    end

    # @!visibility private
    attr_reader :item_pool, :pity_count, :rate_up_items, :rate_up_multiplier

    # @!visibility private
    def pull_with_session(pity_counter:, rate_up:, random:)
      pool = build_pool(rate_up)

      if @pity_count.positive? && pity_counter + 1 >= @pity_count
        rare_pool = pool.select(&:rare)
        item = weighted_sample(rare_pool, random)
        return [item, 0, false]
      end

      item = weighted_sample(pool, random)
      if item.rare
        [item, 0, false]
      else
        [item, pity_counter + 1, rate_up]
      end
    end

    private

    def build_pool(rate_up)
      return @item_pool unless rate_up && !@rate_up_items.empty?

      rate_up_ids = @rate_up_items.to_set(&:id)
      @item_pool.map do |item|
        if rate_up_ids.include?(item.id)
          Item.new(id: item.id, weight: item.weight * @rate_up_multiplier, rare: item.rare)
        else
          item
        end
      end
    end

    def weighted_sample(pool, random)
      total = pool.sum(&:weight)
      roll  = random.rand(total)
      cumulative = 0
      pool.each do |item|
        cumulative += item.weight
        return item if roll < cumulative
      end
      pool.last
    end
  end

  # ガチャの抽選状態（天井カウンター・レートアップ）を保持するセッション。
  #
  # 状態は {#to_h} で Hash に変換して DB に保存し、{.from_h} で復元できます。
  #
  # @example 永続化と復元
  #   record = session.to_h  # => { pity_counter: 42, rate_up: false }
  #   session = Sgmechanics::GachaSession.from_h(gacha: gacha, h: record)
  class GachaSession
    # @return [Integer] 現在の天井カウンター
    attr_reader :pity_counter

    # @return [Boolean] レートアップ中かどうか
    attr_reader :rate_up

    # @param gacha [Gacha] 設定オブジェクト
    # @param pity_counter [Integer] 現在の天井カウンター
    # @param rate_up [Boolean] レートアップ中かどうか
    # @param random [Random] 乱数オブジェクト
    def initialize(gacha:, pity_counter: 0, rate_up: false, random: Random)
      @gacha         = gacha
      @pity_counter  = pity_counter
      @rate_up       = rate_up
      @random        = random
    end

    # 単発抽選を行い、天井カウンターを更新する。
    #
    # @return [Gacha::Item]
    def pull
      item, new_counter, new_rate_up = @gacha.pull_with_session(
        pity_counter: @pity_counter,
        rate_up: @rate_up,
        random: @random
      )
      @pity_counter = new_counter
      @rate_up      = new_rate_up
      item
    end

    # 複数連抽選を行う。
    #
    # @param count [Integer] 抽選回数
    # @return [Array<Gacha::Item>]
    def multi_pull(count:)
      Array.new(count) { pull }
    end

    # セッション状態を Hash に変換する（永続化用）。
    #
    # @return [Hash{Symbol => Object}] `{ pity_counter: Integer, rate_up: Boolean }`
    def to_h
      { pity_counter: @pity_counter, rate_up: @rate_up }
    end

    # Hash からセッションを復元する。
    #
    # @param gacha [Gacha] 設定オブジェクト
    # @param state [Hash{Symbol => Object}] {#to_h} が返した Hash
    # @param random [Random] 乱数オブジェクト
    # @return [GachaSession]
    def self.from_h(gacha:, state:, random: Random)
      new(gacha: gacha, pity_counter: state[:pity_counter], rate_up: state[:rate_up], random: random)
    end
  end
end
