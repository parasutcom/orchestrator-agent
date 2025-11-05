# frozen_string_literal: true

require 'redis'

module Agent
  class Lock
    def initialize(key, ttl: Agent.config.lock_ttl)
      @key = namespaced(key)
      @ttl = ttl
    end

    def with_lock
      acquired = redis.set(@key, '1', nx: true, ex: @ttl)
      raise LockNotAcquired, "Lock #{@key} already held" unless acquired

      yield
    ensure
      redis.del(@key) if acquired
    end

    private

    def redis
      @redis ||= Redis.new(
        url: Agent.config.redis_url,
        connect_timeout: Agent.config.timeouts[:connect],
        read_timeout: Agent.config.timeouts[:read],
        write_timeout: Agent.config.timeouts[:write]
      )
    end

    def namespaced(key)
      [Agent.config.key_prefix, 'lock', key].join(':')
    end
  end
end
