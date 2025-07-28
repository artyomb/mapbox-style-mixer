require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'

StackServiceBase.rack_setup self

CONFIG = YAML.load_file(File.expand_path('styles_config.yaml', __dir__))

helpers do
  def fetch_style(cfg)
    return JSON.parse(Faraday.get(cfg['url']).body) if cfg['url']
    return JSON.parse(File.read(File.expand_path(cfg['file'], __dir__))) if cfg['file']
    halt 400, { error: 'No url or file for style' }.to_json
  end
end

get '/mix' do
  content_type :json
  fetch_style(CONFIG['styles'].first).to_json
end

# get '/fonts/:fontstack/:range.pbf' do
# end
#
# get '/sprites/:sprite_name' do
# end

run Sinatra::Application