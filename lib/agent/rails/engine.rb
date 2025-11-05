# frozen_string_literal: true

module Agent
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace Agent
    end
  end
end
