# frozen_string_literal: true

require 'sidekiq'

module Agent
  # Generic transport-async runner:
  # Executes Executor inside a Sidekiq job with retries + exponential backoff.
  class ExecuteJob
    include Sidekiq::Job

    # Safe defaults if config doesn’t define these knobs
    DEFAULT_QUEUE      = 'orchestrator-agent'
    DEFAULT_RETRY_MAX  = 5
    DEFAULT_BASE_DELAY = 1.0
    DEFAULT_MAX_DELAY  = 60.0
    DEFAULT_JITTER     = true

    # Expose queue/policy so specs (and ops) can inspect current settings
    def self.cfg_queue
      if Agent.config.respond_to?(:queue_name) && Agent.config.queue_name
        Agent.config.queue_name
      else
        DEFAULT_QUEUE
      end
    end

    def self.cfg_policy
      p = if Agent.config.respond_to?(:retry_policy) && Agent.config.retry_policy
            Agent.config.retry_policy
          else
            {}
          end
      {
        max: (p[:max] || DEFAULT_RETRY_MAX),
        base: (p[:base_delay] || DEFAULT_BASE_DELAY),
        cap: (p[:max_delay] || DEFAULT_MAX_DELAY),
        jitter: p.key?(:jitter) ? p[:jitter] : DEFAULT_JITTER
      }
    end

    sidekiq_options queue: -> { Agent::ExecuteJob.cfg_queue },
                    retry: -> { Agent::ExecuteJob.cfg_policy[:max] }

    # Exponential backoff with optional jitter
    sidekiq_retry_in do |attempt, _ex|
      policy = Agent::ExecuteJob.cfg_policy
      delay  = [policy[:cap].to_f, policy[:base].to_f * (2**attempt)].min
      policy[:jitter] ? rand(delay) : delay
    end

    # Args must be JSON-serializable:
    # perform(idem_key, operation, params, caller_id)
    def perform(idem_key, operation, params, caller_id)
      Agent.config.logger.info(
        "[orchestrator-agent] job.start op=#{operation} idem=#{idem_key} caller=#{caller_id}"
      )

      result = Agent::Executor.new.execute(
        operation: operation.to_s,
        params: params || {},
        caller_id: caller_id.to_s,
        idem_key: idem_key
      )

      Agent.config.logger.info(
        "[orchestrator-agent] job.done op=#{operation} idem=#{idem_key}"
      )
      result
    rescue StandardError => e
      Agent.config.logger.error(
        "[orchestrator-agent] job.fail op=#{operation} idem=#{idem_key} error=#{e.class}: #{e.message}"
      )
      # Re-raise so Sidekiq applies the retry policy
      raise
    end
  end
end
