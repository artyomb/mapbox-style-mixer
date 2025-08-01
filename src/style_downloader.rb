require 'yaml'
require 'json'
require 'fileutils'
require 'faraday'
require 'uri'
require 'parallel'

module StyleDownloader
  def self.download_all
    config = $config
    raw_dir = File.expand_path('raw_styles', __dir__)
    fonts_dir = File.expand_path('fonts', __dir__)
    sprites_dir = File.expand_path('sprites', __dir__)

    FileUtils.rm_rf([raw_dir, fonts_dir, sprites_dir])
    FileUtils.mkdir_p([raw_dir, fonts_dir, sprites_dir])

    config['styles'].each do |mix_id, mix_config|
      LOGGER.info "Processing mix style: #{mix_id}"
      
      all_fontstacks = []
      all_sprites = []
      all_glyphs_urls = []
      
      mix_config['sources'].each_with_index do |source_url, index|
        LOGGER.debug "Downloading source #{index + 1}: #{source_url}"
        resp = Faraday.get(source_url)
        raise "Failed to fetch #{source_url}" unless resp.success?
        style_json = JSON.parse(resp.body)
        
        style_id = style_json['id'] || "source_#{index + 1}"
        filename = "#{mix_id}_#{style_id}_#{index + 1}.json"
        File.write(File.join(raw_dir, filename), JSON.pretty_generate(style_json))
        
        all_sprites << { url: style_json['sprite'], name: "#{mix_id}_#{style_id}_#{index + 1}" } if style_json['sprite']
        
        if style_json['glyphs']
          fontstacks = style_json['layers'].map { |l| l.dig('layout', 'text-font') }.compact.flatten.uniq
          all_fontstacks.concat(fontstacks.map { |f| { fontstack: f, style_id: style_id } })
          all_glyphs_urls << style_json['glyphs'] unless all_glyphs_urls.include?(style_json['glyphs'])
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
      
      all_fontstacks.uniq { |f| "#{f[:style_id]}_#{f[:fontstack]}" }.each do |font_info|
        fontstack = font_info[:fontstack]
        style_id = font_info[:style_id]
        style_dir = File.join(fonts_dir, style_id)
        font_dir = File.join(style_dir, fontstack)
        
        next if Dir.exist?(font_dir)
        
        LOGGER.info "Downloading fonts for: #{fontstack} (style: #{style_id})"
        
        ranges = (0..65535).step(256).map { |start| "#{start}-#{start+255}" }
        enc = URI.encode_www_form_component(fontstack)
        
        Parallel.each(ranges, in_threads: 8) do |range|
          FileUtils.mkdir_p(font_dir)
          fname = "#{range}.pbf"
          
          downloaded = false
          all_glyphs_urls.each do |glyphs_url|
            url = glyphs_url.sub('{fontstack}', enc).sub('{range}', range)
            url += '.pbf' unless url.end_with?('.pbf')
            r = Faraday.get(url)
            if r.success?
              File.write(File.join(font_dir, fname), r.body)
              downloaded = true
              break
            end
          end

          unless downloaded
            url2 = "https://demotiles.maplibre.org/font/#{enc}/#{fname}"
            r = Faraday.get(url2)
            File.write(File.join(font_dir, fname), r.body) if r.success?
          end
        end
      end
    end
  end
end 