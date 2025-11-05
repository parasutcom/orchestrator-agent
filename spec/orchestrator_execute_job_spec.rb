# frozen_string_literal: true

require 'agent'

RSpec.describe Agent::ExecuteJob do
  let(:idem_key)  { 'idem-001' }
  let(:operation) { 'echo' }
  let(:params)    { { 'msg' => 'hi' } }
  let(:caller_id) { 'spec' }

  before do
    Agent.configure do |c|
      c.redis_url = ENV['ORCH_REDIS_URL'] || 'redis://127.0.0.1:6379/0'
      c.key_prefix = 'orch_test'
      c.allowed_operations = ['echo']
      c.queue_name = 'orchestrator-agent'
      c.retry_policy = { max: 3, base_delay: 0.01, max_delay: 0.05, jitter: false }
      c.auth = ->(operation:, caller:) { true }
      c.hmac_secret = nil
    end

    class EchoOp
      def self.perform(msg:)
        { echoed: msg }
      end
    end
    Agent.register('echo', EchoOp)
  end

  it 'invokes Executor#execute and returns result' do
    exec = instance_double(Agent::Executor)
    expect(Agent::Executor).to receive(:new).and_return(exec)
    expect(exec).to receive(:execute).with(
      operation: operation, params: params, caller_id: caller_id, idem_key: idem_key
    ).and_return(echoed: 'hi')

    result = described_class.new.perform(idem_key, operation, params, caller_id)
    expect(result).to eq(echoed: 'hi')
  end

  it 're-raises so Sidekiq can retry' do
    allow_any_instance_of(Agent::Executor).to receive(:execute).and_raise('boom')
    expect { described_class.new.perform(idem_key, operation, params, caller_id) }
      .to raise_error(RuntimeError, /boom/)
  end

  it 'accepts string params and Executor symbolizes keys' do
    result = described_class.new.perform(idem_key, 'echo', { 'msg' => 'hey' }, 'spec')
    expect(result).to eq(echoed: 'hey')
  end

  it 'uses configured retry policy in cfg_policy' do
    p = Agent::ExecuteJob.cfg_policy
    expect(p[:max]).to eq(3)
    expect(p[:base]).to eq(0.01)
    expect(p[:cap]).to eq(0.05)
    expect(p[:jitter]).to eq(false)
  end
end
