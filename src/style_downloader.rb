require 'yaml'
require 'json'
require 'fileutils'
require 'faraday'
require 'uri'
require 'parallel'

class StyleDownloader
  def initialize(config = nil)
    @config = config || $config
    @raw_dir = File.expand_path('raw_styles', __dir__)
    @fonts_dir = File.expand_path('fonts', __dir__)
    @sprites_dir = File.expand_path('sprites', __dir__)
  end

  def download_all
    prepare_directories
    @config['styles'].each { |mix_id, mix_config| process_mix_style(mix_id, mix_config) }
  end

  def download_style(mix_id)
    mix_config = @config['styles'][mix_id]
    raise "Style '#{mix_id}' not found in config" unless mix_config
    
    prepare_directories
    process_mix_style(mix_id, mix_config)
  end

  private

  def prepare_directories
    FileUtils.rm_rf([@raw_dir, @fonts_dir, @sprites_dir])
    FileUtils.mkdir_p([@raw_dir, @fonts_dir, @sprites_dir])
  end

  def process_mix_style(mix_id, mix_config)
    style_data = mix_config['sources'].map.with_index { |source_url, index| download_source_style(source_url, mix_id, index) }.compact
    
    sprites = style_data.flat_map { |data| data[:sprites] || [] }
    fontstacks = style_data.flat_map { |data| data[:fontstacks] || [] }
    glyphs_urls = style_data.map { |data| data[:glyphs_url] }.compact.uniq
    
    download_sprites(sprites)
    download_fonts(fontstacks, glyphs_urls)
  end

  def download_source_style(source_config, mix_id, index)
    source_url = source_config.is_a?(Hash) ? source_config['url'] : source_config
    auth_config = source_config.is_a?(Hash) ? source_config['auth'] : nil
    config_prefix = source_config.is_a?(Hash) ? source_config['prefix'] : nil
    
    LOGGER.debug "Downloading source #{index + 1}: #{source_url}"
    
    headers = {}
    if auth_config
      credentials = Base64.strict_encode64("#{auth_config['username']}:#{auth_config['password']}")
      headers['Authorization'] = "Basic #{credentials}"
      LOGGER.debug "Using Basic Auth for #{source_url}"
    end
    
    resp = Faraday.get(source_url, headers: headers)
    raise "Failed to fetch #{source_url}" unless resp.success?
    
    style_json = JSON.parse(resp.body)
    style_id = style_json['id'] || "source_#{index + 1}"
    
    font_prefix = config_prefix || begin
      base = style_json['id'] || style_json['name']&.downcase&.gsub(/\s+/, '_') || "style_#{index + 1}"
      base.gsub(/[^a-zA-Z0-9_]/, '_').squeeze('_')
    end
    style_json['_config_prefix'] = font_prefix
    
    save_style_file(style_json, mix_id, style_id, index)
    
    {
      sprites: extract_sprites(style_json, mix_id, style_id, index),
      fontstacks: extract_fontstacks(style_json, font_prefix),
      glyphs_url: style_json['glyphs']
    }
  end

  def save_style_file(style_json, mix_id, style_id, index)
    filename = "#{mix_id}_#{style_id}_#{index + 1}.json"
    File.write(File.join(@raw_dir, filename), JSON.pretty_generate(style_json))
  end

  def extract_sprites(style_json, mix_id, style_id, index)
    return [] unless style_json['sprite']
    [{ url: style_json['sprite'], name: "#{mix_id}_#{style_id}_#{index + 1}" }]
  end

  def extract_fontstacks(style_json, style_id)
    return [] unless style_json['glyphs']
    
    fontstacks = style_json['layers'].map { |l| l.dig('layout', 'text-font') }.compact.flatten.uniq
    fontstacks.map { |f| { fontstack: f, style_id: style_id } }
  end

  def download_sprites(all_sprites)
    all_sprites.each do |sprite_info|
      dir = File.join(@sprites_dir, sprite_info[:name])
      FileUtils.mkdir_p(dir)
      
      %w[json png].each do |ext|
        r = Faraday.get("#{sprite_info[:url]}.#{ext}")
        File.write(File.join(dir, "sprite.#{ext}"), r.body) if r.success?
      end
    end
  end

  def download_fonts(all_fontstacks, all_glyphs_urls)
    all_fontstacks.uniq { |f| "#{f[:style_id]}_#{f[:fontstack]}" }.each do |font_info|
      download_font_stack(font_info, all_glyphs_urls)
    end
  end

  def download_font_stack(font_info, all_glyphs_urls)
    fontstack = font_info[:fontstack]
    style_id = font_info[:style_id]
    font_dir = File.join(@fonts_dir, style_id, fontstack)
    
    return if Dir.exist?(font_dir)
    
    LOGGER.info "Downloading fonts for: #{fontstack} (style: #{style_id})"
    
    ranges = (0..65535).step(256).map { |start| "#{start}-#{start+255}" }
    enc = fontstack.gsub(' ', '%20')
    
    Parallel.each(ranges, in_threads: 8) do |range|
      download_font_range(font_dir, enc, range, all_glyphs_urls)
    end
  end

  def download_font_range(font_dir, enc, range, all_glyphs_urls)
    FileUtils.mkdir_p(font_dir)
    fname = "#{range}.pbf"
    
    return if try_download_from_glyphs_urls(font_dir, fname, enc, range, all_glyphs_urls)
    try_download_from_fallback(font_dir, fname, enc, range)
  end

  def try_download_from_glyphs_urls(font_dir, fname, enc, range, all_glyphs_urls)
    all_glyphs_urls.each do |glyphs_url|
      url = glyphs_url.sub('{fontstack}', enc).sub('{range}', range)
      url += '.pbf' unless url.end_with?('.pbf')
      
      r = Faraday.get(url)
      if r.success?
        File.write(File.join(font_dir, fname), r.body)
        return true
      end
    end
    false
  end

  def try_download_from_fallback(font_dir, fname, enc, range)
    url = "https://demotiles.maplibre.org/font/#{enc}/#{fname}"
    r = Faraday.get(url)
    File.write(File.join(font_dir, fname), r.body) if r.success?
  end
end 