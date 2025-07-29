require 'yaml'
require 'json'
require 'fileutils'
require 'faraday'
require 'uri'
require 'parallel'

config = YAML.load_file(File.expand_path('styles_config.yaml', __dir__))
raw_dir = File.expand_path('raw_styles', __dir__)
fonts_dir = File.expand_path('fonts', __dir__)
sprites_dir = File.expand_path('sprites', __dir__)

FileUtils.mkdir_p([raw_dir, fonts_dir, sprites_dir])

config['styles'].each do |mix_id, mix_config|
  puts "Processing mix style: #{mix_id}"
  
  all_fontstacks = []
  all_sprites = []
  
  mix_config['sources'].each_with_index do |source_url, index|
    puts "  Downloading source #{index + 1}: #{source_url}"
    resp = Faraday.get(source_url)
    raise "Failed to fetch #{source_url}" unless resp.success?
    style_json = JSON.parse(resp.body)
    
    style_id = style_json['id'] || "source_#{index + 1}"
    filename = "#{mix_id}_#{style_id}_#{index + 1}.json"
    File.write(File.join(raw_dir, filename), JSON.pretty_generate(style_json))
    
    all_sprites << { url: style_json['sprite'], name: "#{mix_id}_#{style_id}_#{index + 1}" } if style_json['sprite']
    
    if style_json['glyphs']
      fontstacks = style_json['layers'].map { |l| l.dig('layout', 'text-font') }.compact.flatten.uniq
      all_fontstacks.concat(fontstacks)
    end
  end
  
  all_sprites.each do |sprite_info|
    dir = File.join(sprites_dir, sprite_info[:name])
    FileUtils.mkdir_p(dir)
    %w[json png].each do |ext|
      r = Faraday.get("#{sprite_info[:url]}.#{ext}")
      File.write(File.join(dir, "sprite.#{ext}"), r.body) if r.success?
    end
  end
  
  all_fontstacks.uniq.each do |fontstack|
    next if Dir.exist?(File.join(fonts_dir, fontstack))
    
    puts "  Downloading fonts for: #{fontstack}"
    first_style = JSON.parse(Faraday.get(mix_config['sources'].first).body)
    next unless (glyphs_url = first_style['glyphs'])
    
    ranges = (0..65535).step(256).map { |start| "#{start}-#{start+255}" }
    enc = URI.encode_www_form_component(fontstack)
    
    Parallel.each(ranges, in_threads: 8) do |range|
      dir = File.join(fonts_dir, fontstack)
      FileUtils.mkdir_p(dir)
      fname = "#{range}.pbf"
      url1 = glyphs_url.sub('{fontstack}', enc).sub('{range}', range)
      url1 += '.pbf' unless url1.end_with?('.pbf')
      r = Faraday.get(url1)
      unless r.success?
        url2 = "https://demotiles.maplibre.org/font/#{enc}/#{fname}"
        r = Faraday.get(url2)
      end
      File.write(File.join(dir, fname), r.body) if r.success?
    end
  end
end 