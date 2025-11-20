# frozen_string_literal: true

require 'action_controller/api'
require 'erb'
require 'kramdown'
require 'openssl'
require 'rack/utils'
require 'securerandom'
require 'yaml'

module Agent
  class ExecutionsController < ActionController::API
    rescue_from Agent::Unauthorized,      with: :render_unauthorized
    rescue_from Agent::Forbidden,         with: :render_forbidden
    rescue_from Agent::UnknownOperation,  with: :render_not_found
    rescue_from Agent::ValidationError,   with: :render_unprocessable
    rescue_from Agent::LockNotAcquired,   with: :render_conflict
    rescue_from Agent::ExecutionError,    with: :render_server_error

    before_action :verify_hmac!

    # POST /.../executions
    # Body JSON: { operation, caller, params: {...}, idem_key?, async? }
    def create
      request.format = :json
      # unwrap nested JSON bodies like { execution: {...} } or { api: {...} }
      payload = params[:execution] || params[:api] || params

      # permit top-level attributes and allow nested params hash
      payload = params[:execution] || params[:api] || params

      # Permit only top-level keys, skip nested params entirely
      permitted = payload.permit(:operation, :caller, :idem_key, :async)

      # Extract params manually (Rails 5.0 bug workaround)
      raw_params =
        if payload[:params].is_a?(ActionController::Parameters)
          payload[:params].to_unsafe_h
        else
          payload[:params] || {}
        end

      op_params = raw_params

      op_name   = permitted[:operation].to_s
      caller_id = permitted[:caller].to_s
      idem_key  = (permitted[:idem_key].presence || SecureRandom.hex(12)).to_s

      # decide whether to run async (using config defaults and per-op overrides)
      async_flag      = truthy?(permitted[:async])
      cfg_async_def   = Agent.config.respond_to?(:async_default) && Agent.config.async_default
      cfg_async_map   = Agent.config.respond_to?(:async_for_ops) && Agent.config.async_for_ops || {}
      requested_async = async_flag || cfg_async_def || cfg_async_map[op_name]

      binding.pry
      
      if requested_async
        Agent::ExecuteJob.perform_async(idem_key, op_name, op_params, caller_id)
        return render json: {
          status: 'accepted',
          state: 'pending',
          idem_key: idem_key
        }, status: :accepted
      end

      # synchronous path
      result = Agent::Executor.new.execute(
        operation: op_name,
        params: op_params,
        caller_id: caller_id,
        idem_key: idem_key
      )

      render json: { status: 'ok', result: result }
    rescue StandardError => e
      ::Rails.logger.error("Agent execution error: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    end

    def status
      permitted = params.permit(:idem_key, :caller)
      idem_key  = permitted[:idem_key].to_s
      caller_id = permitted[:caller].to_s

      auth = Agent.config.auth
      if auth && !auth.call(operation: 'status', caller: caller_id)
        return render_unauthorized(OpenStruct.new(message: 'authorization failed'))
      end

      key = Agent::Idempotency::Key.normalize(idem_key)

      value = Agent::Idempotency::Store.fetch(key)
      return render(json: { status: 'done', result: value }) if value

      render json: { status: 'pending' }, status: :accepted
    end

    def fetch_task
      task_name = params[:task].to_s
      return render json: { error: 'missing task param' }, status: :unprocessable_entity if task_name.blank?

      load_tasks_if_needed

      allowed_ops   = Agent.config.allowed_operations || []
      provider_name = Agent.config.provider || Rails.application.class.module_parent_name.underscore

      # find the single allowed task
      task = Rake::Task.tasks.find do |t|
        allowed_task?(t, allowed_ops) && t.name == task_name
      end

      return render json: { error: "task not found: #{task_name}" }, status: :not_found unless task

      task_data = build_task_metadata(task, provider_name)
      render json: task_data
    rescue StandardError => e
      ::Rails.logger.error("Agent fetch_task error: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: e.message }, status: :internal_server_error
    end

    def fetch_tasks
      load_tasks_if_needed
      allowed = fetch_allowed_tasks
      render json: { tasks: allowed }
    rescue StandardError => e
      ::Rails.logger.error("Agent rake tasks fetch error: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { tasks: [] }, status: :internal_server_error
    end

    private

    def verify_hmac!
      secret = Agent.config.hmac_secret
      return true unless secret

      ts     = request.headers['X-Orch-Timestamp'].to_s
      caller = request.headers['X-Orch-Caller'].to_s
      sig    = request.headers['X-Orch-Signature'].to_s

      return render_unauthorized(OpenStruct.new(message: 'missing auth headers')) if ts.empty? || caller.empty? || sig.empty?

      now = Time.now.to_i
      begin
        tsi = Integer(ts)
      rescue ArgumentError
        return render_unauthorized(OpenStruct.new(message: 'invalid timestamp'))
      end

      skew = Agent.config.hmac_skew || 300
      return render_unauthorized(OpenStruct.new(message: 'timestamp out of range')) if (tsi - now).abs > skew

      # payload: '<timestamp>.<raw_body>'
      payload  = "#{ts}.#{request.raw_post}"
      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, payload)

      # constant-time compare
      match = begin
                Rack::Utils.secure_compare(expected, sig)
              rescue StandardError
                (expected == sig)
              end
      return true if match

      render_unauthorized(OpenStruct.new(message: 'bad signature'))
    end

    def fetch_allowed_tasks
      allowed_ops   = Agent.config.allowed_operations || []
      provider_name = Agent.config.provider || ::Rails.application.class.module_parent_name.underscore

      Rake::Task.tasks
                .select { |task| allowed_task?(task, allowed_ops) }
                .map { |task| build_task_metadata(task, provider_name) }
    end

    def allowed_task?(task, allowed_ops)
      allowed_ops.any? do |op|
        task.name == op || task.name.start_with?("#{op}:")
      end
    end

    def build_task_metadata(task, provider_name)
      {
        name: task.name,
        description: task.comment,
        parameters: task.arg_names.map(&:to_s),
        provider: provider_name,
        instructions: instructions_for_task(task.name.split(':').last)
      }
    end

    def instructions_for_task(task_name)
      return '_Task name is missing._' if task_name.blank?

      mapping = rake_task_docs_mapping
      relative_path = mapping[task_name]
      return "_No instructions available for task `#{task_name}`._" if relative_path.blank?

      path = ::Rails.root.join(relative_path)
      return "_No instructions available for task `#{task_name}`._" unless File.exist?(path)

      md_to_html(File.read(path))
    end

    def rake_task_docs_mapping
      path = ::Rails.root.join('config', 'rake_task_docs.yml')
      return {} unless File.exist?(path)

      raw = ERB.new(File.read(path)).result
      mapping = YAML.safe_load(raw, aliases: true) || {}
      mapping.is_a?(Hash) ? mapping : {}
    end

    def md_to_html(md_content)
      Kramdown::Document.new(md_content, input: 'GFM').to_html
    end

    def load_tasks_if_needed
      Rake.load_rakefile(::Rails.root.join('Rakefile')) if Rake::Task.tasks.empty?
    end

    # Accepts '1/true/yes/on' (case-insensitive) as truthy
    def truthy?(val)
      %w[1 true yes on].include?(val.to_s.strip.downcase)
    end

    def render_unauthorized(e)
      render json: { status: 'error', code: 'unauthorized',    message: e.message }, status: :unauthorized
    end

    def render_forbidden(e)
      render json: { status: 'error', code: 'forbidden',       message: e.message }, status: :forbidden
    end

    def render_not_found(e)
      render json: { status: 'error', code: 'unknown_op',      message: e.message }, status: :not_found
    end

    def render_unprocessable(e)
      render json: {
        status: 'error',
        code: 'validation',
        message: e.message,
        details: e.respond_to?(:details) ? e.details : nil
      }, status: :unprocessable_entity
    end

    def render_conflict(e)
      render json: { status: 'error', code: 'lock_conflict',   message: e.message }, status: :conflict
    end

    def render_server_error(e)
      render json: { status: 'error', code: 'execution_error', message: e.message }, status: :internal_server_error
    end
  end
end
