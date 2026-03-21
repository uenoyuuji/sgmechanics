# frozen_string_literal: true

require "date"

RSpec.describe Sgmechanics::DayCycle do
  # JST = UTC+9, reset at 05:00:00 JST
  let(:lc) { described_class.new(reset_hour: 5, utc_offset: "+09:00") }

  # Helper: build a Time in JST
  def jst(year, month, day, hour, min = 0, sec = 0)
    Time.new(year, month, day, hour, min, sec, "+09:00")
  end

  describe "#game_day" do
    it "returns current date when at or after reset time" do
      t = jst(2024, 1, 10, 5, 0, 0) # exactly 05:00
      expect(lc.game_day(t)).to eq(Date.new(2024, 1, 10))
    end

    it "returns previous date when before reset time" do
      t = jst(2024, 1, 10, 4, 59, 59) # one second before reset
      expect(lc.game_day(t)).to eq(Date.new(2024, 1, 9))
    end

    it "returns previous date at 00:00 (midnight)" do
      t = jst(2024, 1, 10, 0, 0, 0)
      expect(lc.game_day(t)).to eq(Date.new(2024, 1, 9))
    end
  end

  describe "#last_reset" do
    it "returns today's reset when at or after reset time" do
      t = jst(2024, 1, 10, 6, 0, 0)
      expect(lc.last_reset(t)).to eq(jst(2024, 1, 10, 5, 0, 0))
    end

    it "returns yesterday's reset when before reset time" do
      t = jst(2024, 1, 10, 4, 0, 0)
      expect(lc.last_reset(t)).to eq(jst(2024, 1, 9, 5, 0, 0))
    end
  end

  describe "#next_reset" do
    it "returns tomorrow's reset when at or after reset time" do
      t = jst(2024, 1, 10, 5, 0, 0)
      expect(lc.next_reset(t)).to eq(jst(2024, 1, 11, 5, 0, 0))
    end

    it "returns today's reset when before reset time" do
      t = jst(2024, 1, 10, 4, 0, 0)
      expect(lc.next_reset(t)).to eq(jst(2024, 1, 10, 5, 0, 0))
    end
  end

  describe "#seconds_until_next_reset" do
    it "returns correct seconds" do
      t = jst(2024, 1, 10, 4, 0, 0) # 1 hour before reset
      expect(lc.seconds_until_next_reset(t)).to eq(3600)
    end
  end

  describe "#reset_occurred_between?" do
    it "returns true when a reset is between from and to" do
      from = jst(2024, 1, 10, 4, 0, 0)
      to   = jst(2024, 1, 10, 6, 0, 0) # straddles reset at 05:00
      expect(lc.reset_occurred_between?(from: from, to: to)).to be true
    end

    it "returns false when no reset is between from and to" do
      from = jst(2024, 1, 10, 5, 30, 0)
      to   = jst(2024, 1, 10, 7, 0, 0)
      expect(lc.reset_occurred_between?(from: from, to: to)).to be false
    end

    it "returns false when from and to are both before reset" do
      from = jst(2024, 1, 10, 2, 0, 0)
      to   = jst(2024, 1, 10, 4, 59, 59)
      expect(lc.reset_occurred_between?(from: from, to: to)).to be false
    end
  end

  describe "custom reset time" do
    it "supports minute and second precision" do
      lc2 = described_class.new(reset_hour: 5, reset_minute: 30, reset_second: 0, utc_offset: "+09:00")
      expect(lc2.game_day(jst(2024, 1, 10, 5, 29, 59))).to eq(Date.new(2024, 1, 9))
      expect(lc2.game_day(jst(2024, 1, 10, 5, 30, 0))).to eq(Date.new(2024, 1, 10))
    end
  end
end
