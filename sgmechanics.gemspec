# frozen_string_literal: true

require_relative 'lib/sgmechanics/version'

Gem::Specification.new do |spec|
  spec.name    = 'sgmechanics'
  spec.version = Sgmechanics::VERSION
  spec.authors = ['sgmechanics']
  spec.summary = 'Social game mechanics library'

  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.require_paths = ['lib']

  spec.add_development_dependency 'rake',          '~> 13.0'
  spec.add_development_dependency 'rspec',         '~> 3.0'
  spec.add_development_dependency 'rubocop',       '~> 1.72'
  spec.add_development_dependency 'rubocop-rake',  '~> 0.6'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.0'
  spec.add_development_dependency 'yard',          '~> 0.9'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
