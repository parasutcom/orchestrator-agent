# frozen_string_literal: true

Agent::Rails::Engine.routes.draw do
  post '/executions', to: 'executions#create'
  get  '/executions/status/:idem_key', to: 'executions#status'
  get  '/executions/fetch_tasks', to: 'executions#fetch_tasks'
  get '/executions/fetch_task', to: 'executions#fetch_task'
end
