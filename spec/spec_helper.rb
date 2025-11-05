# frozen_string_literal: true

require 'bundler/setup'

# load your gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'agent'

# ensure the Sidekiq job class is available
begin
  Agent::ExecuteJob
rescue NameError
  require 'agent/execute_job'
end

# support helpers
Dir[File.join(__dir__, 'support/**/*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.formatter = :documentation if ENV['CI'] != 'true'

  # isolate Redis keys between examples
  config.around(:each) do |example|
    with_clean_orchestrator_keys { example.run }
  end
end
