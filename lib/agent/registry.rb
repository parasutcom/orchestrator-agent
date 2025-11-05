# frozen_string_literal: true

module Agent
  class Registry
    def initialize
      @mutex = Mutex.new
      @ops   = {}
    end

    # name: String/Symbol, op: a class or callable object
    def register(name, op)
      key = name.to_s
      @mutex.synchronize { @ops[key] = op }
      key
    end

    # fetch the registered op, or nil
    def fetch(name)
      @mutex.synchronize { @ops[name.to_s] }
    end

    # array of operation names
    def names
      @mutex.synchronize { @ops.keys.sort }
    end
  end

  # global registry instance (simple default)
  def self.registry
    @registry ||= Registry.new
  end

  def self.register(name, op)
    registry.register(name, op)
  end

  def self.fetch(name)
    registry.fetch(name)
  end
end
