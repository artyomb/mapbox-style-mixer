require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'
require 'slim'

StackServiceBase.rack_setup self

set :public_folder, File.expand_path('public', __dir__)

$config = YAML.load_file(ENV['CONFIG_PATH'] || File.expand_path('configs/styles_config.yaml', __dir__))
START_TIME = Time.now
$initialization_status = { state: 'error', progress: 0, message: 'Initializing...' }

require_relative 'style_downloader'
require_relative 'style_mixer'
require_relative 'sprite_merger'
require_relative 'style_initializer'

Thread.new { StyleInitializer.initialize_with_retry }

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
        fonts: extract_fonts_from_style(style_id),
        sprites: get_sprite_info(style_id)
      }
    end
  end

  def get_sprite_info(style_id)
    sprite_dir = File.expand_path('sprite', __dir__)
    ['', '@2x'].map { |type| 
      [type, %w[png json].select { |ext| File.exist?("#{sprite_dir}/#{style_id}_sprite#{type}.#{ext}") }]
    }.select { |_, files| files.any? }
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
      .dig('layers')&.flat_map { |layer| extract_fonts_from_layer(layer) }
      &.uniq { |font| font[:path] } || []
  rescue => e
    LOGGER.error "Error extracting fonts for #{style_id}: #{e.message}"
    []
  end

  def extract_fonts_from_layer(layer)
    font_config = layer.dig('layout', 'text-font')
    return [] unless font_config
    
    case font_config
    when Array then font_config.map { |font| { name: font, path: font } }
    when Hash then extract_fonts_from_stops(font_config['stops'])
    else []
    end
  end

  def extract_fonts_from_stops(stops)
    return [] unless stops&.is_a?(Array)
    
    stops.flat_map { |stop| stop[1] if stop.is_a?(Array) && stop[1] }
         .compact.map { |fonts| fonts.is_a?(Array) ? fonts : [fonts] }
         .flatten.map { |font| { name: font, path: font } }
  end
  

  
  def validate_auth_config(source)
    return unless source.is_a?(Hash) && source['auth']
    missing = ['username', 'password'] - source['auth'].keys
    raise "Missing auth fields: #{missing}" if missing.any?
  end
  
  def get_safe_config(config = $config)
    config.dup.tap do |safe_config|
      safe_config['styles'] = safe_config['styles'].transform_values do |style_config|
        style_config.dup.tap do |safe_style|
          safe_style['sources'] = safe_style['sources'].map do |source|
            validate_auth_config(source)
            source.is_a?(Hash) && source['auth'] ? 
              source.dup.tap { |s| s['auth']['password'] = '***' if s['auth']['password'] } :
              source
          end
        end
      end
    end
  end
  
  def serve_sprite_file(mix_id, extension, high_dpi = false)
    suffix = high_dpi ? "@2x" : ""
    sprite_file = File.expand_path("sprite/#{mix_id}#{suffix}.#{extension}", __dir__)
    
    if File.exist?(sprite_file)
      content_type extension == 'json' ? :json : :png
      File.read(sprite_file)
    else
      halt 404, { error: "Sprite #{extension}#{suffix} not found for mix '#{mix_id}'" }.to_json
    end
  end
  
  def get_available_fonts
    fonts_dir = File.expand_path('fonts', __dir__)
    Dir.glob("#{fonts_dir}/**/*/").select { |path| 
      Dir.glob("#{path}*.pbf").any?
    }.map { |path| 
      path.gsub("#{fonts_dir}/", '').chomp('/')
    }
  end
  
  def serve_font_file_fallback(fontstack, range)
    decoded_fontstack = URI.decode_www_form_component(fontstack)
    font_file = File.join(File.expand_path('fonts', __dir__), decoded_fontstack, "#{range}.pbf")
    
    if File.exist?(font_file)
      LOGGER.debug "Serving font file: #{font_file}"
      content_type 'application/octet-stream'
      File.read(font_file)
    else
      LOGGER.warn "Font file not found: #{font_file}"
      content_type :json
      get_available_fonts.to_json
    end
  end
end

get '/' do
  @styles = get_styles_data
  @total_sources = @styles.sum { |s| s[:sources_count] }
  @uptime = Time.now - START_TIME
  @config = get_safe_config
  @initialization_status = $initialization_status
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

get '/sprite/:mix_id@2x.json' do
  serve_sprite_file(params[:mix_id], 'json', true)
end

get '/sprite/:mix_id@2x.png' do
  serve_sprite_file(params[:mix_id], 'png', true)
end

get '/fonts/*/:range.pbf' do
  serve_font_file_fallback(params[:splat].first, params[:range])
end

get '/fonts.json' do
  content_type :json
  get_available_fonts.to_json
end

get '/refresh' do
  $initialization_status = { state: 'loading', progress: 0, message: 'Starting refresh...' }
  $config = YAML.load_file(ENV['CONFIG_PATH'] || File.expand_path('configs/styles_config.yaml', __dir__))
  Thread.new { StyleInitializer.initialize_with_retry }
  redirect '/'
end

get '/map' do
  slim :map, layout: :map_layout
end

run Sinatra::Application