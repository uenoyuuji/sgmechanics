# frozen_string_literal: true

module Sgmechanics
  # スタミナ（AP/BP）の回復タイマーを管理するクラス。
  #
  # 「今の時刻」を外から渡す設計のため、テストや再現が容易です。
  # 時刻は Unix タイムスタンプ（Integer または Float）で扱います。
  #
  # @example 基本的な使い方
  #   now     = Time.now.to_i
  #   stamina = Sgmechanics::Stamina.new(120, 300, now + 3000, 0, now)
  #   stamina.value           # => 110
  #   stamina.seconds_for_max # => 3000
  class Stamina
    # スタミナが不足しているときに {#decrease} が raise するエラー
    class DecreaseError < StandardError; end

    # @return [Numeric] 回復が完了する時刻（Unix タイムスタンプ）
    attr_reader :completion_time

    # @return [Integer] 最大値を超えて保持しているスタミナ量
    attr_reader :overflowed_stamina

    # @param max_stamina [Integer] スタミナの最大値
    # @param seconds_per_stamina [Numeric] 1 スタミナあたりの回復秒数
    # @param completion_time [Numeric] 回復完了時刻（Unix タイムスタンプ）
    # @param overflowed_stamina [Integer] 最大値を超えた分のスタミナ
    # @param now [Numeric] 現在時刻（Unix タイムスタンプ）
    def initialize(max_stamina, seconds_per_stamina, completion_time, overflowed_stamina, now)
      @max_stamina = max_stamina
      @seconds_per_stamina = seconds_per_stamina
      @completion_time = completion_time
      @overflowed_stamina = overflowed_stamina
      @now = now

      fix
    end

    # スタミナが満タンかどうかを返す。
    #
    # @return [Boolean]
    def full?
      @now >= @completion_time
    end

    # 現在のスタミナ値を返す（overflow 込み）。
    #
    # @return [Integer]
    def value
      t = full? ? @max_stamina : [@max_stamina - ((@completion_time - @now) / @seconds_per_stamina.to_f).ceil, 0].max
      t + @overflowed_stamina
    end

    # 満タンになるまでの秒数を返す。満タンなら 0。
    #
    # @return [Numeric]
    def seconds_for_max
      return 0 if @now >= @completion_time

      @completion_time - @now
    end

    # 次の 1 スタミナが回復するまでの秒数を返す。満タンなら 0。
    #
    # @return [Numeric]
    def seconds_for_next
      sfm = seconds_for_max
      return sfm if sfm.zero?

      ret = sfm % @seconds_per_stamina
      ret.zero? ? @seconds_per_stamina : ret
    end

    # スタミナを即座に空にする。
    #
    # @return [self]
    def to_empty
      @overflowed_stamina = 0
      @completion_time = @now + (@seconds_per_stamina * @max_stamina)
      self
    end

    # スタミナを即座に満タンにする。すでに満タンなら何もしない。
    #
    # @return [self]
    def to_fill
      return self if full?

      @completion_time = @now
      self
    end

    # スタミナを増やす。最大値を超えた分は overflow に積まれる。
    #
    # @param amount [Integer] 増加量（正の整数）
    # @return [self]
    # @raise [ArgumentError] amount が 0 以下の場合
    def increase(amount)
      raise ArgumentError if amount <= 0

      if full?
        @overflowed_stamina += amount
        return self
      end

      diff = @max_stamina - value
      if diff >= amount
        @completion_time -= @seconds_per_stamina * amount
      else
        @completion_time = @now
        @overflowed_stamina = amount - diff
      end

      self
    end

    # スタミナを消費する。overflow から優先的に消費する。
    #
    # @param amount [Integer] 消費量（正の整数）
    # @return [self]
    # @raise [ArgumentError] amount が 0 以下の場合
    # @raise [DecreaseError] 現在のスタミナが amount を下回る場合
    def decrease(amount)
      raise ArgumentError if amount <= 0
      raise DecreaseError if value < amount

      if @overflowed_stamina >= amount
        @overflowed_stamina -= amount
        return self
      end

      amount -= @overflowed_stamina
      @overflowed_stamina = 0

      @completion_time += (amount * @seconds_per_stamina)

      self
    end

    private

    def fix
      @completion_time = [@completion_time, @now].max
    end
  end
end
