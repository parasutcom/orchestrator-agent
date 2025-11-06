# frozen_string_literal: true

module Agent
  class Config
    attr_accessor :redis_url,
                  :timeouts,
                  :idempotency_ttl,
                  :lock_ttl,
                  :logger,
                  :auth,
                  :allowed_operations,
                  :key_prefix,
                  :hmac_secret,
                  :hmac_skew,
                  :queue_name,
                  :async_default,
                  :async_for_ops,
                  :retry_policy,
                  :provider

    def initialize
      @redis_url          = ENV['ORCH_REDIS_URL'] || 'redis://127.0.0.1:6379/0'
      @timeouts           = { connect: 0.5, read: 1.0, write: 1.0 }
      @idempotency_ttl    = 24 * 60 * 60
      @lock_ttl           = 60
      @logger             = (defined?(Logger) ? Logger.new($stdout) : nil)
      @auth               = nil
      @allowed_operations = []
      @key_prefix         = 'orchestrator-agent'
      @hmac_secret        = ENV['ORCH_HMAC_SECRET']
      @hmac_skew          = 300
      @provider = nil
      @queue_name    = 'orchestrator-agent'
      @async_default = false
      @async_for_ops = {}
      @retry_policy  = { max: 5, base_delay: 1.0, max_delay: 60.0, jitter: true }
    end
  end
end
