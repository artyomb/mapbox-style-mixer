require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'
require 'slim'

StackServiceBase.rack_setup self

$config = YAML.load_file(ENV['CONFIG_PATH'] || File.expand_path('configs/styles_config.yaml', __dir__))
START_TIME = Time.now

require_relative 'style_downloader'
require_relative 'style_mixer'
require_relative 'sprite_merger'

begin
  StyleDownloader.new($config).download_all
  StyleMixer.new($config).mix_all_styles
  LOGGER.info "Styles successfully loaded and mixed on startup"
rescue => e
  LOGGER.error "Error loading styles on startup: #{e.message}"
end

helpers do
  def fetch_style(mix_id, config = $config)
    mix_config = config['styles'][mix_id]
    halt 404, { error: "Style '#{mix_id}' not found" }.to_json unless mix_config
    
    mixed_file = File.expand_path("mixed_styles/#{mix_id}.json", __dir__)
    halt 404, { error: "Mixed style '#{mix_id}' not available" }.to_json unless File.exist?(mixed_file)
    
    JSON.parse(File.read(mixed_file))
  end
  
  def get_styles_data(config = $config)
    config['styles'].keys.map do |style_id|
      {
        id: style_id,
        name: config['styles'][style_id]['name'],
        endpoint: "/styles/#{style_id}",
        sources_count: config['styles'][style_id]['sources'].length
      }
    end
  end
  
  def serve_sprite_file(mix_id, extension)
    sprite_file = File.expand_path("sprite/#{mix_id}.#{extension}", __dir__)
    
    if File.exist?(sprite_file)
      content_type extension == 'json' ? :json : :png
      File.read(sprite_file)
    else
      halt 404, { error: "Sprite #{extension} not found for mix '#{mix_id}'" }.to_json
    end
  end
  
  def serve_font_file(fontstack, range)
    decoded_fontstack = URI.decode_www_form_component(fontstack)
    font_file = File.join(File.expand_path('fonts', __dir__), decoded_fontstack, "#{range}.pbf")
    
    if File.exist?(font_file)
      LOGGER.debug "Serving font file: #{font_file}"
      content_type 'application/octet-stream'
      File.read(font_file)
    else
      LOGGER.warn "Font file not found: #{font_file}"
      halt 404, { error: "Font file not found" }.to_json
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
  style = fetch_style(params[:style])
  
  style_json = style.to_json
  style_json.gsub!('"/sprite/', "\"#{request.base_url}/sprite/")
  style_json.gsub!('"/fonts/', "\"#{request.base_url}/fonts/")
  
  style_json
end

get '/sprite/:mix_id.json' do
  serve_sprite_file(params[:mix_id], 'json')
end

get '/sprite/:mix_id.png' do
  serve_sprite_file(params[:mix_id], 'png')
end

get '/fonts/*/:range.pbf' do
  serve_font_file(params[:splat].first, params[:range])
end

get '/refresh' do
  Thread.new do
    begin
      $config = YAML.load_file(ENV['CONFIG_PATH'] || File.expand_path('configs/styles_config.yaml', __dir__))
      StyleDownloader.new($config).download_all
      StyleMixer.new($config).mix_all_styles
      LOGGER.info "Styles refreshed and mixed successfully"
    rescue => e
      LOGGER.error "Error refreshing styles: #{e.message}"
    end
  end
  redirect '/'
end

get '/map' do
  slim :map, layout: :map_layout
end

run Sinatra::Application