# frozen_string_literal: true

# A class with class-level .perform(**)
class ClassPerformOp
  def self.perform(a:, b:)
    { sum: a + b }
  end
end

# A class with instance-level #perform(**)
class InstancePerformOp
  def initialize(mult: 2)
    @mult = mult
  end

  def perform(x:)
    { product: x * @mult }
  end
end

# A callable adapter-like object with #call(**)
class CallableAdapter
  def initialize(prefix:)
    @prefix = prefix
  end

  def call(word:)
    { out: "#{@prefix}#{word}" }
  end
end

# Counting op to verify idempotency/locks
class CountingOp
  class << self; attr_accessor :calls end
  def self.reset!
    self.calls = 0
  end

  def self.perform(x:)
    self.calls += 1
    { seen: self.calls, x: x }
  end
end
