# frozen_string_literal: true

require 'agent'

RSpec.describe 'orchestrator registry' do
  it 'registers and fetches by string key' do
    Agent.register('echo', ClassPerformOp)
    expect(Agent.fetch('echo')).to eq(ClassPerformOp)
  end

  it 'overrides existing keys deterministically' do
    Agent.register('x', ClassPerformOp)
    Agent.register('x', InstancePerformOp)
    expect(Agent.fetch('x')).to eq(InstancePerformOp)
  end
end
