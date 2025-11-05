# frozen_string_literal: true

require 'agent'

RSpec.describe 'orchestrator smoke' do
  before do
    Agent.configure do |c|
      c.redis_url = ENV['ORCH_REDIS_URL'] || 'redis://127.0.0.1:6379/0'
      c.allowed_operations = ['echo']
      c.key_prefix = 'orch_test'
    end

    class EchoOp
      def self.perform(msg:)
        { echoed: msg }
      end
    end
    Agent.register('echo', EchoOp)
  end

  it 'executes once and returns cached on second call' do
    ex = Agent::Executor.new

    first  = ex.execute(operation: 'echo', params: { msg: 'hi' }, caller_id: 'spec', idem_key: 'idem-1')
    second = ex.execute(operation: 'echo', params: { msg: 'hi' }, caller_id: 'spec', idem_key: 'idem-1')

    expect(first).to eq(echoed: 'hi')
    expect(second).to eq(echoed: 'hi')
  end
end
