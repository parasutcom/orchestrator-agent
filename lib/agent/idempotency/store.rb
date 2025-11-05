# frozen_string_literal: true

require 'json'
require 'redis'

module Agent
  module Idempotency
    module Store
      module_function

      # Returns [hit, value]
      # - hit:   true if returned from cache, false if freshly computed
      # - value: JSON-serializable result from the block or cache
      #
      # NOTE: We assume a higher-level lock around this (your Executor already does it).
      def fetch_or_store(key:, ttl: Agent.config.idempotency_ttl, symbolize: true)
        rkey = redis_key(key)

        if (cached = redis.get(rkey))
          return [true, parse_json(cached, symbolize: symbolize)]
        end

        value = yield
        # cache only successful results; exceptions bubble up
        redis.set(rkey, JSON.dump(value), ex: ttl)
        [false, value]
      end

      # Read a cached value or nil
      def fetch(key, symbolize: true)
        data = redis.get(redis_key(key))
        data ? parse_json(data, symbolize: symbolize) : nil
      end
      alias read fetch

      # Write a value with TTL (upsert)
      def write(key, value, ttl: Agent.config.idempotency_ttl)
        redis.set(redis_key(key), JSON.dump(value), ex: ttl)
        true
      end

      # Delete a cached value (rarely used, handy for tests/tools)
      def delete(key)
        redis.del(redis_key(key)).positive?
      end

      # Compose the Redis key with the configured namespace
      def redis_key(key)
        [Agent.config.key_prefix, 'idem', key].join(':')
      end

      # Expose the Redis client (memoized)
      def redis
        @redis ||= Redis.new(
          url: Agent.config.redis_url,
          connect_timeout: Agent.config.timeouts[:connect],
          read_timeout: Agent.config.timeouts[:read],
          write_timeout: Agent.config.timeouts[:write]
        )
      end

      # ---- internal helpers ----
      def parse_json(str, symbolize:)
        JSON.parse(str, symbolize_names: symbolize)
      end
      private_class_method :parse_json
    end
  end
end
