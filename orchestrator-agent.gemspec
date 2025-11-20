# frozen_string_literal: true

require_relative 'lib/agent/version'

Gem::Specification.new do |spec|
  spec.name = 'orchestrator-agent'
  spec.version = '0.1.2'
  spec.authors = ['berksurmeli']
  spec.email = ['hasan.surmeli@parasut.com']

  spec.summary = 'Write a short summary, because RubyGems requires one.'
  spec.description = 'Write a longer description or delete this line.'
  spec.homepage = 'https://www.example.com'

  spec.metadata['allowed_push_host'] = "Set to your gem server 'https://example.com'"

  spec.metadata = {
    'homepage_uri' => 'https://www.example.com'
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir[
    'lib/**/*',
    'app/**/*',        # <-- REQUIRED for Rails engines
    'config/**/*',     # <-- include engine routes
    'db/**/*',         # <-- if you have migrations / seeds
    'README*',
    'LICENSE*'
  ]
  spec.require_paths = ['lib']

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.add_runtime_dependency 'kramdown', '~> 2.3.2'
  spec.add_runtime_dependency 'kramdown-parser-gfm', '~> 1.1.0'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
