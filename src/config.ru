require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'
require 'slim'
require_relative 'style_downloader'

StackServiceBase.rack_setup self

CONFIG = YAML.load_file('/configs/styles_config.yaml')
START_TIME = Time.now

begin
  StyleDownloader.download_all
  LOGGER.info "Styles successfully loaded on startup"
rescue => e
  LOGGER.error "Error loading styles on startup: #{e.message}"
end

helpers do
  def fetch_style(mix_id)
    mix_config = CONFIG['styles'][mix_id]
    halt 404, { error: "Style '#{mix_id}' not found" }.to_json unless mix_config
    
    resp = Faraday.get(mix_config['sources'].first)
    raise "Failed to fetch #{mix_config['sources'].first}" unless resp.success?
    JSON.parse(resp.body)
  end
  
  def get_styles_data
    CONFIG['styles'].keys.map do |style_id|
      {
        id: style_id,
        name: CONFIG['styles'][style_id]['name'],
        endpoint: "/styles/#{style_id}",
        sources_count: CONFIG['styles'][style_id]['sources'].length
      }
    end
  end
end

get '/' do
  @styles = get_styles_data
  @total_sources = @styles.sum { |s| s[:sources_count] }
  @uptime = Time.now - START_TIME
  slim :index
end

get '/api/styles' do
  content_type :json
  {
    available_styles: get_styles_data
  }.to_json
end

get '/styles/:style' do
  content_type :json
  fetch_style(params[:style]).to_json
end

get '/refresh' do
  Thread.new do
    begin
      StyleDownloader.download_all
    end
  end
  redirect '/'
end

run Sinatra::Application