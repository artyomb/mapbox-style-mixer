require 'sinatra'
require 'faraday'
require 'faraday/retry'
require 'faraday/net_http_persistent'
require 'stack-service-base'

StackServiceBase.rack_setup self

configure do
  # f_client =  Faraday.new url: "https://...", ssl: { verify: false } do |f|
  #     f.request  :retry, max: 2, interval: 0.2, backoff_factor: 2
  #     # f.response :json, content_type: /\bjson$/
  #     f.options.timeout      = 15
  #     f.options.open_timeout = 10
  #     f.adapter :net_http_persistent, pool_size: 10, idle_timeout: 60
  # end
  # set :http_clients, f_client
end

get '/styles/:style'

helpers do
  def foo
  end
end

run Sinatra::Application