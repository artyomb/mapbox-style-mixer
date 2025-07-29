require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'

StackServiceBase.rack_setup self

CONFIG = YAML.load_file(File.expand_path('styles_config.yaml', __dir__))

helpers do
  def fetch_style(mix_id)
    mix_config = CONFIG['styles'][mix_id]
    halt 404, { error: "Style '#{mix_id}' not found" }.to_json unless mix_config
    
    source_url = mix_config['sources'].first
    resp = Faraday.get(source_url)
    raise "Failed to fetch #{source_url}" unless resp.success?
    JSON.parse(resp.body)
  end
end

get '/' do
  content_type :json
  {
    available_styles: CONFIG['styles'].keys.map { |style_id|
      {
        id: style_id,
        name: CONFIG['styles'][style_id]['name'],
        endpoint: "/styles/#{style_id}",
        sources_count: CONFIG['styles'][style_id]['sources'].length
      }
    }
  }.to_json
end

get '/styles/:style' do
  content_type :json
  fetch_style(params[:style]).to_json
end

run Sinatra::Application