# frozen_string_literal: true

require 'json'
require 'digest'

module Agent
  module Idempotency
    module Key
      module_function

      # Deterministic SHA256 over { op, params (sorted), caller [, idem_key] }
      #
      # - params can be any JSON-serializable object; we deep-sort Hash keys so
      #   {"a":1,"b":2} and {"b":2,"a":1} produce the same digest.
      # - idem_key is OPTIONAL; when present it is part of the hash, otherwise omitted.
      def build(op:, params:, caller_id:, idem_key: nil)
        safe_params = params.is_a?(Hash) || params.is_a?(Array) ? params : {}

        payload = {
          op: op.to_s,
          params: canonicalize(safe_params),
          caller: caller_id.to_s
        }
        payload[:idem_key] = idem_key.to_s unless idem_key.nil?

        Digest::SHA256.hexdigest(JSON.generate(payload))
      end

      # Useful when you receive an externally provided idem_key and just need a
      # consistent String form (e.g., for the status endpoint).
      def normalize(idem_key)
        idem_key.to_s
      end

      # ---- internal helpers ----

      # Deeply sort hash keys to ensure canonical JSON
      def canonicalize(obj)
        case obj
        when Hash
          obj.keys.sort.each_with_object({}) do |k, h|
            h[k] = canonicalize(obj[k])
          end
        when Array
          obj.map { |v| canonicalize(v) }
        else
          obj
        end
      end
      private_class_method :canonicalize
    end
  end
end
