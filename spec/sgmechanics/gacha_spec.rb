# frozen_string_literal: true

RSpec.describe Sgmechanics::Gacha do
  let(:iron)     { described_class::Item.new(id: :iron,     weight: 70, rare: false) }
  let(:silver)   { described_class::Item.new(id: :silver,   weight: 20, rare: false) }
  let(:gold)     { described_class::Item.new(id: :gold,     weight:  8, rare: true) }
  let(:platinum) { described_class::Item.new(id: :platinum, weight:  2, rare: true) }

  let(:pool)  { [iron, silver, gold, platinum] }
  let(:gacha) { described_class.new(item_pool: pool, pity_count: 5) }

  describe 'Item' do
    it 'is frozen' do
      expect(iron).to be_frozen
    end
  end

  describe '#pull' do
    it 'returns an Item from the pool' do
      item = gacha.pull(random: Random.new(0))
      expect(pool).to include(item)
    end
  end

  describe '#multi_pull' do
    it 'returns the requested number of items' do
      items = gacha.multi_pull(count: 10, random: Random.new(42))
      expect(items.size).to eq(10)
      items.each { |i| expect(pool).to include(i) }
    end
  end

  describe 'GachaSession pity (ceiling)' do
    it 'forces a rare at pity_count pulls' do
      # Use a gacha with only non-rare items to guarantee counter increments,
      # then check the counter resets to 0 after hitting ceiling.
      non_rare = described_class::Item.new(id: :common, weight: 100, rare: false)
      ceiling_rare = described_class::Item.new(id: :rare, weight: 1, rare: true)
      ceiling_pool = [non_rare, ceiling_rare]

      g = described_class.new(item_pool: ceiling_pool, pity_count: 3)
      s = g.new_session(pity_counter: 0, random: Random.new(99))

      # Pull 1 and 2: non-rare, counter increments
      pull1 = s.pull
      expect(pull1.rare).to be false
      expect(s.pity_counter).to eq(1)

      pull2 = s.pull
      expect(pull2.rare).to be false
      expect(s.pity_counter).to eq(2)

      # Pull 3: pity_counter(2) + 1 >= pity_count(3) → forced rare
      pull3 = s.pull
      expect(pull3.rare).to be true
      expect(s.pity_counter).to eq(0)
    end

    it 'resets counter when a rare is pulled naturally' do
      all_rare = [described_class::Item.new(id: :rare, weight: 100, rare: true)]
      g = described_class.new(item_pool: all_rare, pity_count: 10)
      s = g.new_session(pity_counter: 3, random: Random.new(0))
      item = s.pull
      expect(item.rare).to be true
      expect(s.pity_counter).to eq(0)
    end
  end

  describe 'GachaSession rate_up' do
    it 'increases weight of rate_up_items when rate_up is true' do
      rate_up_rare = described_class::Item.new(id: :r_up,   weight:  5, rare: true)
      normal_rare  = described_class::Item.new(id: :r_norm, weight:  5, rare: true)
      common_item  = described_class::Item.new(id: :common, weight: 90, rare: false)
      item_pool    = [common_item, rate_up_rare, normal_rare]

      g = described_class.new(
        item_pool: item_pool,
        pity_count: 0,
        rate_up_items: [rate_up_rare],
        rate_up_multiplier: 10
      )

      # With rate_up=true, r_up has weight 50 vs r_norm weight 5 → r_up should win ~10x more
      results = 1000.times.map { g.new_session(rate_up: true, random: Random.new(rand(10_000))).pull }
      rate_up_count = results.count { |i| i.id == :r_up }
      normal_count  = results.count { |i| i.id == :r_norm }
      expect(rate_up_count).to be > normal_count * 5
    end
  end

  describe 'GachaSession#to_h / #from_h' do
    it 'serializes and deserializes state' do
      session = gacha.new_session(pity_counter: 3, rate_up: true)
      state = session.to_h
      expect(state).to eq({ pity_counter: 3, rate_up: true })

      restored = Sgmechanics::GachaSession.from_h(gacha: gacha, state: state)
      expect(restored.pity_counter).to eq(3)
      expect(restored.rate_up).to be true
    end
  end

  describe 'GachaSession#multi_pull' do
    it 'returns correct count' do
      session = gacha.new_session(random: Random.new(1))
      results = session.multi_pull(count: 5)
      expect(results.size).to eq(5)
    end
  end
end
