# frozen_string_literal: true

RSpec.describe Sgmechanics::Stamina do
  let(:now) { 10_000 }
  let(:full_pool) { build(completion_time: now - 100) }
  let(:pool_five) { build(completion_time: now + (5 * seconds_per_stamina)) } # value = 5
  let(:max_stamina) { 10 }
  let(:seconds_per_stamina) { 360 }

  def build(completion_time:, overflowed_stamina: 0)
    described_class.new(seconds_per_stamina, max_stamina, completion_time, overflowed_stamina, now)
  end

  describe "#value" do
    context "when full" do
      it { expect(full_pool.value).to eq(max_stamina) }
    end

    context "when partially filled" do
      it "returns current stamina" do
        expect(pool_five.value).to eq(5)
      end
    end

    context "with overflow stamina" do
      it "includes overflow in the value" do
        pool = build(completion_time: now, overflowed_stamina: 3)
        expect(pool.value).to eq(max_stamina + 3)
      end
    end
  end

  describe "#full?" do
    it "returns true when full" do
      expect(full_pool.full?).to be true
    end

    it "returns false when not full" do
      expect(pool_five.full?).to be false
    end
  end

  describe "#seconds_for_max" do
    it "returns 0 when full" do
      expect(full_pool.seconds_for_max).to eq(0)
    end

    it "returns seconds remaining until full" do
      expect(pool_five.seconds_for_max).to eq(5 * seconds_per_stamina)
    end
  end

  describe "#seconds_for_next" do
    it "returns 0 when full" do
      expect(full_pool.seconds_for_next).to eq(0)
    end

    context "when exactly on a tick boundary" do
      it "returns seconds_per_stamina" do
        # sfm = 5 * 360 = 1800, 1800 % 360 = 0 → returns full interval
        expect(pool_five.seconds_for_next).to eq(seconds_per_stamina)
      end
    end

    context "when mid-tick" do
      it "returns time until next tick" do
        pool = build(completion_time: now + (4 * seconds_per_stamina) + 100)
        expect(pool.seconds_for_next).to eq(100)
      end
    end
  end

  describe "#increase" do
    it "raises ArgumentError for zero" do
      expect { full_pool.increase(0) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for negative value" do
      expect { full_pool.increase(-1) }.to raise_error(ArgumentError)
    end

    context "when not full" do
      it "increases stamina within max" do
        pool = build(completion_time: now + (5 * seconds_per_stamina)) # value = 5
        pool.increase(3)
        expect(pool.value).to eq(8)
        expect(pool.overflowed_stamina).to eq(0)
      end

      it "fills exactly to max with no overflow" do
        pool = build(completion_time: now + (5 * seconds_per_stamina)) # value = 5
        pool.increase(5)
        expect(pool.value).to eq(max_stamina)
        expect(pool.overflowed_stamina).to eq(0)
        expect(pool.full?).to be true
      end

      it "adds excess beyond max to overflow" do
        pool = build(completion_time: now + (5 * seconds_per_stamina)) # value = 5
        pool.increase(7) # 5 + 7 = 12 → overflow = 2
        expect(pool.value).to eq(max_stamina + 2)
        expect(pool.overflowed_stamina).to eq(2)
      end
    end

    context "when already full" do
      it "adds entirely to overflow" do
        full_pool.increase(3)
        expect(full_pool.overflowed_stamina).to eq(3)
        expect(full_pool.value).to eq(max_stamina + 3)
      end
    end

    it "returns self" do
      expect(full_pool.increase(1)).to be(full_pool)
    end
  end

  describe "#decrease" do
    it "raises ArgumentError for zero" do
      expect { full_pool.decrease(0) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for negative value" do
      expect { full_pool.decrease(-1) }.to raise_error(ArgumentError)
    end

    it "raises DecreaseError when value is insufficient" do
      pool = build(completion_time: now + (8 * seconds_per_stamina)) # value = 2
      expect { pool.decrease(3) }.to raise_error(Sgmechanics::Stamina::DecreaseError)
    end

    context "when overflow covers the decrease" do
      it "reduces overflow only, leaving pool full" do
        pool = build(completion_time: now, overflowed_stamina: 5)
        pool.decrease(3)
        expect(pool.overflowed_stamina).to eq(2)
        expect(pool.full?).to be true
      end
    end

    context "when decrease comes from regular stamina" do
      it "extends completion_time accordingly" do
        pool = build(completion_time: now) # value = 10, full
        pool.decrease(3)
        expect(pool.value).to eq(7)
        expect(pool.full?).to be false
      end
    end

    context "when decrease spans overflow and regular stamina" do
      it "clears overflow then reduces regular stamina" do
        pool = build(completion_time: now, overflowed_stamina: 2) # value = 12
        pool.decrease(5) # consume 2 overflow + 3 regular → value = 7
        expect(pool.overflowed_stamina).to eq(0)
        expect(pool.value).to eq(7)
      end
    end

    it "returns self" do
      expect(full_pool.decrease(1)).to be(full_pool)
    end
  end

  describe "#to_empty" do
    it "sets value to 0 and clears overflow" do
      pool = build(completion_time: now, overflowed_stamina: 3)
      pool.to_empty
      expect(pool.value).to eq(0)
      expect(pool.overflowed_stamina).to eq(0)
    end

    it "returns self" do
      expect(full_pool.to_empty).to be(full_pool)
    end
  end

  describe "#to_fill" do
    it "fills the pool when not full" do
      pool_five.to_fill
      expect(pool_five.full?).to be true
      expect(pool_five.value).to eq(max_stamina)
    end

    it "is a no-op when already full" do
      ct = full_pool.completion_time
      full_pool.to_fill
      expect(full_pool.completion_time).to eq(ct)
    end

    it "returns self" do
      expect(pool_five.to_fill).to be(pool_five)
    end
  end

  describe "initialize" do
    it "clamps completion_time to now when given a past time" do
      pool = build(completion_time: now - 1000)
      expect(pool.full?).to be true
      expect(pool.value).to eq(max_stamina)
    end
  end
end
