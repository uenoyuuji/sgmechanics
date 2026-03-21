# frozen_string_literal: true

require "bundler/setup"
require "sgmechanics"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.disable_monkey_patching!
  config.order = :random
end
