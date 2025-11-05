# frozen_string_literal: true

require 'agent'

RSpec.describe 'orchestrator async smoke' do
  before do
    Agent.configure do |c|
      c.redis_url = ENV['ORCH_REDIS_URL'] || 'redis://127.0.0.1:6379/0'
      c.allowed_operations = ['echo']
      c.key_prefix = 'orch_test'
      c.queue_name = 'orchestrator-agent'
      c.retry_policy = { max: 2, base_delay: 0.01, max_delay: 0.05, jitter: false }
    end

    class EchoOp
      def self.perform(msg:)
        { echoed: msg }
      end
    end
    Agent.register('echo', EchoOp)
  end

  it 'ExecuteJob performs the same business result as direct Executor' do
    sync = Agent::Executor.new.execute(
      operation: 'echo',
      params: { msg: 'hello' },
      caller_id: 'spec',
      idem_key: 'idem-sync-1'
    )
    expect(sync).to eq(echoed: 'hello')

    job_result = Agent::ExecuteJob.new.perform(
      'idem-async-1', 'echo', { 'msg' => 'hello' }, 'spec'
    )
    expect(job_result).to eq(echoed: 'hello')
  end
end
