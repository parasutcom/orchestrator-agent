# frozen_string_literal: true

module Agent
  module Adapters
    class SidekiqJob
      def initialize(job_class, queue: nil)
        @job_class = job_class
        @queue     = queue
      end

      def call(**params)
        ensure_sidekiq!

        raise Agent::ExecutionError, 'job class missing' unless @job_class
        raise Agent::ExecutionError, 'job class must respond to perform_async' unless @job_class.respond_to?(:perform_async)

        jid =
          if @queue
            @job_class.set(queue: @queue).perform_async(**params)
          else
            @job_class.perform_async(**params)
          end

        { enqueued: true, jid: jid, queue: (@queue || default_queue_name) }
      rescue StandardError => e
        raise Agent::ExecutionError, e.message
      end

      private

      def ensure_sidekiq!
        unless defined?(Sidekiq)
          raise Agent::ConfigurationError, 'Sidekiq is not loaded. Add `sidekiq` to your app and require it before using SidekiqJob.'
        end
      end

      def default_queue_name
        'default'
      end
    end
  end
end
