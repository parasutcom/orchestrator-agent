# frozen_string_literal: true

require 'rake'
require 'stringio'

module Agent
  module Adapters
    class RakeTask
      def initialize(task_name, env: {})
        @task_name = task_name.to_s
        @base_env  = stringify_keys(env || {})
      end

      # Accepts keyword params; we expose them to the task via ENV.
      # Returns the captured stdout/stderr as a string.
      def call(**params)
        ensure_rake_loaded!

        task = Rake::Task[@task_name] # raises if not defined
        task.reenable

        out = StringIO.new
        err = StringIO.new
        old_out, old_err = $stdout, $stderr
        $stdout = out
        $stderr = err

        begin
          with_env(@base_env.merge(stringify_keys(params))) do
            task.invoke
          end
        rescue SystemExit => e
          out.puts "Task exited with status #{e.status}"
        rescue RuntimeError, NameError => e
          # NameError: task not found; RuntimeError: task blew up
          err.puts "Error: #{e.class} - #{e.message}"
          err.puts e.backtrace.join("\n") if e.backtrace
        ensure
          $stdout = old_out
          $stderr = old_err
        end

        [out.string, err.string].reject(&:empty?).join("\n").presence || "(no output)"
      end

      private

      def ensure_rake_loaded!
        # Load Rakefile if tasks aren’t available yet
        return if Rake::Task.task_defined?(@task_name)

        app = Rake.application
        # If Rails is present, prefer its Rakefile
        if defined?(Rails) && Rails.respond_to?(:root)
          rakefile = File.join(Rails.root.to_s, 'Rakefile')
          app.load_rakefile if File.exist?(rakefile)
        else
          # Try current directory Rakefile
          %w[Rakefile rakefile Rakefile.rb rakefile.rb].each do |rf|
            if File.exist?(rf)
              app.load_rakefile
              break
            end
          end
        end
      end

      def with_env(vars)
        old = {}
        vars.each { |k, v| (old[k] = ENV[k]); ENV[k] = v.to_s }
        yield
      ensure
        vars.each_key { |k| ENV[k] = old[k] }
      end

      def stringify_keys(h)
        out = {}
        (h || {}).each { |k, v| out[k.to_s] = v }
        out
      end
    end
  end
end
