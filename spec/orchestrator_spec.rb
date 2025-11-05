# frozen_string_literal: true

RSpec.describe Agent do
  it 'has a version number' do
    expect(Agent::VERSION).not_to be nil
  end
end
