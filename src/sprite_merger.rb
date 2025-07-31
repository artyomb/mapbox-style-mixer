require 'json'
require 'fileutils'
require 'chunky_png'

module SpriteMerger
  def self.merge_sprites_for_mix(mix_id)
    LOGGER.info "Starting sprite merging for #{mix_id}"
    
    sprite_dirs = find_sprite_dirs(mix_id)
    return log_no_sprites(mix_id) if sprite_dirs.empty?
    
    output_dir = create_output_dir
    sprite_data = collect_sprite_data(sprite_dirs)
    
    return log_no_sprites(mix_id) if sprite_data.empty?
    
    success = merge_sprites_with_chunky_png(sprite_data, output_dir, mix_id)
    
    if success
      LOGGER.info "Successfully merged #{sprite_data.length} sprites for #{mix_id}"
      { png: File.join(output_dir, "#{mix_id}.png"), json: File.join(output_dir, "#{mix_id}.json") }
    else
      LOGGER.error "Failed to merge sprites for #{mix_id}"
      nil
    end
  end
  
  def self.merge_all_sprites
    config = $config
    
    LOGGER.info "Starting merging of all sprites"
    
    config['styles'].each do |mix_id, mix_config|
      merge_sprites_for_mix(mix_id)
    rescue => e
      LOGGER.error "Error merging sprites for #{mix_id}: #{e.message}"
    end
    
    LOGGER.info "Sprite merging completed"
  end
  
  private
  
  def self.find_sprite_dirs(mix_id)
    sprites_dir = File.expand_path('sprites', __dir__)
    Dir.glob("#{sprites_dir}/#{mix_id}_*").select { |d| Dir.exist?(d) }
  end
  
  def self.create_output_dir
    output_dir = File.expand_path('sprite', __dir__)
    FileUtils.mkdir_p(output_dir)
    output_dir
  end
  
  def self.collect_sprite_data(sprite_dirs)
    sprite_dirs.map do |dir|
      png_file = File.join(dir, 'sprite.png')
      json_file = File.join(dir, 'sprite.json')
      
      next unless File.exist?(png_file) && File.exist?(json_file)
      
      begin
        png = ChunkyPNG::Image.from_file(png_file)
        json = JSON.parse(File.read(json_file))
        LOGGER.debug "Loaded sprite from #{dir}: #{png.width}x#{png.height}"
        { png: png, json: json, dir: dir }
      rescue => e
        LOGGER.error "Failed to load sprite from #{dir}: #{e.message}"
        nil
      end
    end.compact
  end
  
  def self.merge_sprites_with_chunky_png(sprite_data, output_dir, mix_id)
    return false if sprite_data.empty?
    
    begin
      return copy_single_sprite(sprite_data.first, output_dir, mix_id) if sprite_data.length == 1
      
      merged_sprite, merged_json = merge_multiple_sprites(sprite_data)
      
      merged_sprite.save(File.join(output_dir, "#{mix_id}.png"))
      File.write(File.join(output_dir, "#{mix_id}.json"), JSON.pretty_generate(merged_json))
      
      LOGGER.debug "Saved merged sprite: #{merged_sprite.width}x#{merged_sprite.height}"
      true
    rescue => e
      LOGGER.error "Error merging sprites: #{e.message}"
      false
    end
  end
  
  def self.copy_single_sprite(sprite_info, output_dir, mix_id)
    source_png = File.join(sprite_info[:dir], 'sprite.png')
    source_json = File.join(sprite_info[:dir], 'sprite.json')
    
    FileUtils.cp(source_png, File.join(output_dir, "#{mix_id}.png"))
    FileUtils.cp(source_json, File.join(output_dir, "#{mix_id}.json"))
    
    LOGGER.debug "Copied single sprite from #{sprite_info[:dir]}"
    true
  end
  
  def self.merge_multiple_sprites(sprite_data)
    total_width = sprite_data.map { |s| s[:png].width }.max
    total_height = sprite_data.map { |s| s[:png].height }.sum
    
    merged_sprite = ChunkyPNG::Image.new(total_width, total_height, ChunkyPNG::Color::TRANSPARENT)
    merged_json = {}
    
    current_y = 0
    
    sprite_data.each do |sprite_info|
      png = sprite_info[:png]
      json = sprite_info[:json]
      
      merged_sprite.compose!(png, 0, current_y)
      
      json.each do |icon_name, icon_data|
        merged_json[icon_name] = {
          'width' => icon_data['width'],
          'height' => icon_data['height'],
          'pixelRatio' => icon_data['pixelRatio'],
          'x' => icon_data['x'],
          'y' => icon_data['y'] + current_y
        }
      end
      
      current_y += png.height
    end
    
    [merged_sprite, merged_json]
  end
  
  def self.log_no_sprites(mix_id)
    LOGGER.warn "No sprite directories found for #{mix_id}"
    nil
  end
end 