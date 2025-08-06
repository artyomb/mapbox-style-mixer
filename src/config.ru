require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'
require 'slim'

StackServiceBase.rack_setup self

$config = YAML.load_file(ENV['CONFIG_PATH'] || File.expand_path('configs/styles_config.yaml', __dir__))
START_TIME = Time.now
$initialization_status = { state: 'error', progress: 0, message: 'Initializing...' }

require_relative 'style_downloader'
require_relative 'style_mixer'
require_relative 'sprite_merger'

Thread.new do
  begin
    LOGGER.info "Starting background initialization..."
    $initialization_status = { state: 'loading', progress: 20, message: 'Downloading source styles...' }
    LOGGER.info "Downloading source styles..."
    StyleDownloader.new($config).download_all
    
    $initialization_status = { state: 'loading', progress: 70, message: 'Mixing styles...' }
    LOGGER.info "Mixing styles..."
    StyleMixer.new($config).mix_all_styles
    
    $initialization_status = { state: 'ready', progress: 100, message: 'Ready' }
    LOGGER.info "Styles successfully loaded and mixed on startup"
  rescue => e
    $initialization_status = { state: 'error', progress: 0, message: "Error: #{e.message}" }
    LOGGER.error "Error loading styles on startup: #{e.message}"
  end
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
      style_config = config['styles'][style_id]
      {
        id: style_id,
        name: style_config['name'],
        endpoint: "/styles/#{style_id}",
        sources_count: style_config['sources'].length,
        sources: style_config['sources'],
        config: style_config,
        mixed_style: load_mixed_style_info(style_id),
        fonts: extract_fonts_from_style(style_id)
      }
    end
  end
  
  def load_mixed_style_info(style_id)
    mixed_file = File.expand_path("mixed_styles/#{style_id}.json", __dir__)
    return { layers_count: 0, sources_count: 0 } unless File.exist?(mixed_file)
    
    mixed_style = JSON.parse(File.read(mixed_file))
    {
      layers_count: mixed_style.dig('layers')&.size || 0,
      sources_count: mixed_style.dig('sources')&.size || 0
    }
  rescue => e
    LOGGER.error "Error loading mixed style info for #{style_id}: #{e.message}"
    { layers_count: 0, sources_count: 0 }
  end
  
  def extract_fonts_from_style(style_id)
    mixed_file = File.expand_path("mixed_styles/#{style_id}.json", __dir__)
    return [] unless File.exist?(mixed_file)
    
    JSON.parse(File.read(mixed_file))
      .dig('layers')&.flat_map { |layer| layer.dig('layout', 'text-font') || [] }
      &.map { |font| { name: font, path: font } }
      &.uniq || []
  rescue => e
    LOGGER.error "Error extracting fonts for #{style_id}: #{e.message}"
    []
  end
  

  
  def get_safe_config(config = $config)
    config.dup.tap do |safe_config|
      safe_config['styles'] = safe_config['styles'].transform_values do |style_config|
        style_config.dup.tap do |safe_style|
          safe_style['sources'] = safe_style['sources'].map do |source|
            source.is_a?(Hash) && source['auth'] ? 
              source.dup.tap { |s| s['auth']['password'] = '***' if s['auth']['password'] } :
              source
          end
        end
      end
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
  @config = get_safe_config
  slim :index
end

get '/status' do
  content_type :json
  $initialization_status.to_json
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
  $initialization_status = { state: 'loading', progress: 0, message: 'Starting refresh...' }
  
  Thread.new do
    begin
      $initialization_status = { state: 'loading', progress: 20, message: 'Downloading source styles...' }
      $config = YAML.load_file(ENV['CONFIG_PATH'] || File.expand_path('configs/styles_config.yaml', __dir__))
      StyleDownloader.new($config).download_all
      
      $initialization_status = { state: 'loading', progress: 70, message: 'Mixing styles...' }
      StyleMixer.new($config).mix_all_styles
      
      $initialization_status = { state: 'ready', progress: 100, message: 'Ready' }
      LOGGER.info "Styles refreshed and mixed successfully"
    rescue => e
      $initialization_status = { state: 'error', progress: 0, message: "Error: #{e.message}" }
      LOGGER.error "Error refreshing styles: #{e.message}"
    end
  end
  redirect '/'
end

get '/map' do
  slim :map, layout: :map_layout
end

run Sinatra::Application