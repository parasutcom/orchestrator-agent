# frozen_string_literal: true

require 'agent'

RSpec.describe Agent::Executor do
  before do
    Agent.configure do |c|
      c.redis_url = ENV['ORCH_REDIS_URL'] || 'redis://127.0.0.1:6379/0'
      c.key_prefix = 'orch_test'
      c.allowed_operations = %w[sum product prefix count echo]
      c.auth = ->(operation:, caller:) { true }
      c.idempotency_ttl = 60 # keep small in tests
      c.lock_ttl = 2
    end

    # register ops
    Agent.register('sum', ClassPerformOp)
    Agent.register('product', InstancePerformOp)
    Agent.register('prefix', CallableAdapter.new(prefix: 'PRE-'))
    Agent.register('count', CountingOp)
    Agent.register('echo', Class.new do
                             def self.perform(msg:)
                               { echoed: msg }
                                       end
                           end)
  end

  subject(:executor) { described_class.new }

  describe 'invocation styles' do
    it 'invokes class .perform(**) (ClassPerformOp)' do
      res = executor.execute(operation: 'sum', params: { a: 3, b: 4 }, caller_id: 'spec')
      expect(res).to eq(sum: 7)
    end

    it 'invokes instance #perform(**) (InstancePerformOp)' do
      res = executor.execute(operation: 'product', params: { x: 5 }, caller_id: 'spec')
      expect(res).to eq(product: 10)
    end

    it 'invokes callable #call(**) (CallableAdapter)' do
      res = executor.execute(operation: 'prefix', params: { word: 'ok' }, caller_id: 'spec')
      expect(res).to eq(out: 'PRE-ok')
    end

    it 'symbolizes incoming param keys' do
      res = executor.execute(operation: 'sum', params: { 'a' => 1, 'b' => 2 }, caller_id: 'spec')
      expect(res).to eq(sum: 3)
    end
  end

  describe 'errors & policy' do
    # it "raises UnknownOperation for missing registry" do
    #   expect {
    #     executor.execute(operation: "missing", params: {}, caller_id: "spec")
    #   }.to raise_error(Agent::UnknownOperation)
    # end

    it 'enforces allowlist (Forbidden) when op not listed' do
      Agent.configure { |c| c.allowed_operations = %w[sum] }
      expect do
        executor.execute(operation: 'prefix', params: { word: 'x' }, caller_id: 'spec')
      end.to raise_error(Agent::Forbidden, /operation not allowed/i)
    end

    it 'checks auth hook (Unauthorized) when policy denies' do
      Agent.configure { |c| c.auth = ->(operation:, caller:) { false } }
      expect do
        executor.execute(operation: 'sum', params: { a: 1, b: 1 }, caller_id: 'intruder')
      end.to raise_error(Agent::Unauthorized)
    end
  end

  describe 'idempotency + locks' do
    before { CountingOp.reset! }

    it 'returns cached result on second identical call' do
      r1 = executor.execute(operation: 'count', params: { x: 42 }, caller_id: 'spec', idem_key: 'idem-1')
      r2 = executor.execute(operation: 'count', params: { x: 42 }, caller_id: 'spec', idem_key: 'idem-1')
      expect(r1).to eq(seen: 1, x: 42)
      expect(r2).to eq(seen: 1, x: 42) # cached
    end

    it 'computes again for different idem_key' do
      r1 = executor.execute(operation: 'count', params: { x: 1 }, caller_id: 'spec', idem_key: 'idem-A')
      r2 = executor.execute(operation: 'count', params: { x: 1 }, caller_id: 'spec', idem_key: 'idem-B')
      expect(r1).to eq(seen: 1, x: 1)
      expect(r2).to eq(seen: 2, x: 1)
    end

    it 'propagates LockNotAcquired if lock guard fails' do
      # Simulate lock conflict by stubbing Lock#with_lock to raise
      allow_any_instance_of(Agent::Lock).to receive(:with_lock).and_raise(Agent::LockNotAcquired.new('busy'))
      expect do
        executor.execute(operation: 'echo', params: { msg: 'hi' }, caller_id: 'spec', idem_key: 'idem-Z')
      end.to raise_error(Agent::LockNotAcquired)
    end
  end

  describe 'unexpected errors are wrapped as ExecutionError' do
    it 'wraps unknown runtime errors' do
      bad_op = Class.new do
        def self.perform(**)
          raise 'boom'
        end
      end
      Agent.register('bad', bad_op)
      Agent.configure { |c| c.allowed_operations += ['bad'] }

      expect do
        executor.execute(operation: 'bad', params: {}, caller_id: 'spec')
      end.to raise_error(Agent::ExecutionError, /boom/)
    end
  end
end
