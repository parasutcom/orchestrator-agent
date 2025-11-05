# frozen_string_literal: true

module Agent
  class Executor
    def initialize(logger: Agent.config.logger)
      @logger = logger
    end

    # Public API
    # - operation: String/Symbol (registry key)
    # - params:    Hash (JSON-serializable)
    # - caller_id: String
    # - idem_key:  String (optional external idempotency key)
    #
    # Returns JSON-serializable result
    def execute(operation:, params:, caller_id:, idem_key: nil)
      op_name = operation.to_s

      authorize!(op_name, caller_id)
      enforce_allowlist!(op_name)

      key = Idempotency::Key.build(op: op_name, params: params, caller_id: caller_id, idem_key: idem_key)

      # Align lock namespace with the idempotency entry
      Lock.new("idem:#{key}", ttl: Agent.config.lock_ttl).with_lock do
        hit, value = Idempotency::Store.fetch_or_store(key: key, ttl: Agent.config.idempotency_ttl) do
          puts '================================================='
          puts 'invoking operation...'
          puts op_name.inspect
          puts params.inspect
          puts '================================================='
          invoke!(op_name, params)
        end

        log(event: 'execute.finish', operation: op_name, caller_id: caller_id, idempotent: hit)
        value
      end
    rescue LockNotAcquired => e
      log(event: 'execute.lock_conflict', operation: op_name, caller_id: caller_id, error: e.message)
      raise
    rescue UnknownOperation, ValidationError, Forbidden, Unauthorized => e
      log(event: 'execute.error', operation: op_name, caller_id: caller_id, error: e.class.name, message: e.message)
      raise
    rescue StandardError => e
      log(event: 'execute.unexpected', operation: op_name, caller_id: caller_id, error: e.class.name, message: e.message)
      raise ExecutionError, e.message
    end

    private

    # Resolve and invoke the registered target in a predictable order:
    # 1) Adapter or object with #call(**kwargs)
    # 2) Class with class method .perform(**kwargs)
    # 3) Class with instance method #perform(**kwargs)
    def invoke!(op_name, params)
      op = Agent.fetch(op_name)
      raise UnknownOperation, "unknown operation: #{op_name}" unless op

      puts '================================================='
      puts op.inspect

      kwargs = symbolize_keys(params)

      puts '================================================='
      puts kwargs.inspect
      # 1) Callable (adapters like RakeTask, SidekiqJob)
      return op.call(**kwargs) if op.respond_to?(:call) && !op.is_a?(Class)

      # 2) Class-level .perform(**)
      if op.is_a?(Class) && op.respond_to?(:perform) && !op.instance_methods(false).include?(:perform)
        return op.perform(**kwargs)
      end

      # 3) Instance-level #perform(**)
      if op.is_a?(Class) && op.instance_methods(false).include?(:perform)
        return op.new.perform(**kwargs)
      end

      # 4) Non-class object with #perform(**)
      return op.perform(**kwargs) if !op.is_a?(Class) && op.respond_to?(:perform)

      raise ExecutionError, "operation #{op_name} is not invocable (needs #call or #perform)"
    end

    def authorize!(op_name, caller_id)
      auth = Agent.config.auth
      return unless auth

      ok = auth.respond_to?(:call) ? auth.call(operation: op_name, caller: caller_id) : true
      raise Unauthorized, "authorization failed for #{caller_id}" unless ok
    end

    def enforce_allowlist!(op_name)
      allow = Agent.config.allowed_operations
      return if allow.nil? || allow.empty?
      raise Forbidden, "operation not allowed: #{op_name}" unless allow.include?(op_name)
    end

    def symbolize_keys(hash)
      return {} unless hash

      h = {}
      hash.each { |k, v| h[(k.respond_to?(:to_sym) ? k.to_sym : k)] = v }
      h
    end

    def log(payload)
      return unless @logger

      @logger.info("[orchestrator-agent] #{payload.inspect}")
    end
  end
end
