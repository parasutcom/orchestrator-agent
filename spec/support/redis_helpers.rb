# frozen_string_literal: true

require 'redis'

def redis_client
  url = Agent.config.redis_url || ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0'
  Redis.new(url: url)
end

def with_clean_orchestrator_keys
  prefix = Agent.config.key_prefix || 'orchestrator-agent'
  r = redis_client
  begin
    keys = r.keys("#{prefix}:*")
    r.del(*keys) unless keys.empty?
    yield
  ensure
    keys = r.keys("#{prefix}:*")
    r.del(*keys) unless keys.empty?
  end
end
