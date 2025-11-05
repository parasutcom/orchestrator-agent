# frozen_string_literal: true

module Agent
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class Unauthorized < Error; end
  class Forbidden < Error; end

  class UnknownOperation < Error; end
  class ValidationError < Error
    attr_reader :details
    def initialize(message = 'validation failed', details: nil)
      @details = details
      super(message)
    end
  end
  class ExecutionError < Error; end

  class LockNotAcquired < Error; end
  class IdempotencyConflict < Error; end
end
