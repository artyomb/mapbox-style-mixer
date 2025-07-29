require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'
require 'slim'
require_relative 'style_downloader'
require_relative 'style_mixer'

StackServiceBase.rack_setup self

CONFIG = YAML.load_file('/configs/styles_config.yaml')
START_TIME = Time.now

begin
  StyleDownloader.download_all
  StyleMixer.mix_all_styles
  LOGGER.info "Styles successfully loaded and mixed on startup"
rescue => e
  LOGGER.error "Error loading styles on startup: #{e.message}"
end

helpers do
  def fetch_style(mix_id)
    mix_config = CONFIG['styles'][mix_id]
    halt 404, { error: "Style '#{mix_id}' not found" }.to_json unless mix_config
    
    mixed_file = File.expand_path("mixed_styles/#{mix_id}.json", __dir__)
    halt 404, { error: "Mixed style '#{mix_id}' not available" }.to_json unless File.exist?(mixed_file)
    
    JSON.parse(File.read(mixed_file))
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

get '/styles' do
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
      StyleMixer.mix_all_styles
      LOGGER.info "Styles refreshed and mixed successfully"
    rescue => e
      LOGGER.error "Error refreshing styles: #{e.message}"
    end
  end
  redirect '/'
end

run Sinatra::Application