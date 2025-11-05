# frozen_string_literal: true

require 'agent'

RSpec.describe Agent::ExecuteJob do
  let(:idem_key)  { 'idem-001' }
  let(:operation) { 'echo' }
  let(:params)    { { 'msg' => 'hi' } }
  let(:caller_id) { 'spec' }

  before do
    # minimal config for async/retries
    Agent.configure do |c|
      c.redis_url = ENV['ORCH_REDIS_URL'] || 'redis://127.0.0.1:6379/0'
      c.allowed_operations = ['echo']
      c.key_prefix     = 'orch_test'
      c.queue_name     = 'orchestrator-agent'
      c.retry_policy   = { max: 3, base_delay: 0.01, max_delay: 0.05, jitter: false }
      c.auth           = ->(**) { true }
      c.hmac_secret    = nil # disable HMAC for tests
    end

    # a tiny operation
    class EchoOp
      def self.perform(msg:)
        { echoed: msg }
      end
    end

    Agent.register('echo', EchoOp)
  end

  it 'calls Executor#execute and returns the op result' do
    exec = instance_double(Agent::Executor)
    expect(Agent::Executor).to receive(:new).and_return(exec)
    expect(exec).to receive(:execute).with(
      operation: operation,
      params: params,
      caller_id: caller_id,
      idem_key: idem_key
    ).and_return('echoed' => 'hi')

    result = described_class.new.perform(idem_key, operation, params, caller_id)
    expect(result).to eq('echoed' => 'hi')
  end

  it 're-raises on failure so Sidekiq can retry' do
    allow_any_instance_of(Agent::Executor).to receive(:execute).and_raise('boom')
    expect do
      described_class.new.perform(idem_key, operation, params, caller_id)
    end.to raise_error(RuntimeError, /boom/)
  end
end
