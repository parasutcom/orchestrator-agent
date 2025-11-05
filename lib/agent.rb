# frozen_string_literal: true

require_relative 'agent/version'
require_relative 'agent/config'
require_relative 'agent/errors'
require_relative 'agent/lock'
require_relative 'agent/idempotency/key'
require_relative 'agent/idempotency/store'
require_relative 'agent/registry'
require_relative 'agent/executor'
require_relative 'agent/adapters/rake_task'
require_relative 'agent/adapters/sidekiq_job'

# Rails integration (optional)
if defined?(Rails)
  require_relative 'agent/rails/engine'
  require_relative 'agent/executions_controller'
end

module Agent
  class << self
    def config
      @config ||= Agent::Config.new
    end

    def configure
      yield(config)
    end
  end

  class Error < StandardError; end
end
