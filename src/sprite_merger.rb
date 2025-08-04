require 'json'
require 'fileutils'

module SpriteMerger
  def self.merge_sprites_for_mix(mix_id)
    LOGGER.info "Starting sprite merging for #{mix_id}"
    
    sprite_dirs = find_sprite_dirs(mix_id)
    return log_no_sprites(mix_id) if sprite_dirs.empty?
    
    sprite_files = collect_sprite_files(sprite_dirs)
    return log_no_sprites(mix_id) if sprite_files.empty?
    
    success = merge_sprites_with_imagemagick(sprite_files, mix_id)
    
    if success
      LOGGER.info "Successfully merged #{sprite_files.length} sprites for #{mix_id}"
      { png: File.join(output_dir, "#{mix_id}_sprite.png"), json: File.join(output_dir, "#{mix_id}_sprite.json") }
    else
      LOGGER.error "Failed to merge sprites for #{mix_id}"
      nil
    end
  end
  
  def self.merge_all_sprites(config = $config)
    LOGGER.info "Starting merging of all sprites"
    prepare_sprite_directory
    
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
  
  def self.output_dir
    output_dir = File.expand_path('sprite', __dir__)
    FileUtils.mkdir_p(output_dir)
    output_dir
  end
  
  def self.prepare_sprite_directory
    sprite_dir = File.expand_path('sprite', __dir__)
    FileUtils.rm_rf(sprite_dir) if Dir.exist?(sprite_dir)
    FileUtils.mkdir_p(sprite_dir)
  end
  
  def self.collect_sprite_files(sprite_dirs)
    sprite_dirs.map do |dir|
      png_file = File.join(dir, 'sprite.png')
      json_file = File.join(dir, 'sprite.json')
      
      next unless File.exist?(png_file) && File.exist?(json_file)
      
      begin
        json_data = JSON.parse(File.read(json_file))
        LOGGER.debug "Found sprite from #{dir}"
        { png_file: png_file, json_file: json_file, json_data: json_data, dir: dir }
      rescue => e
        LOGGER.error "Failed to load sprite from #{dir}: #{e.message}"
        nil
      end
    end.compact
  end
  
  def self.merge_sprites_with_imagemagick(sprite_files, mix_id)
    return false if sprite_files.empty?
    
    begin
      return copy_single_sprite(sprite_files.first, mix_id) if sprite_files.length == 1
      
      output_png = File.join(output_dir, "#{mix_id}_sprite.png")
      output_json = File.join(output_dir, "#{mix_id}_sprite.json")
      
      png_files = sprite_files.map { |sf| sf[:png_file] }
      
      success = merge_png_files_imagemagick(png_files, output_png)
      return false unless success
      
      merged_json = merge_json_metadata(sprite_files, png_files)
      File.write(output_json, JSON.pretty_generate(merged_json))
      
      LOGGER.debug "Saved merged sprite using ImageMagick"
      true
    rescue => e
      LOGGER.error "Error merging sprites: #{e.message}"
      false
    end
  end
  
  def self.merge_png_files_imagemagick(png_files, output_file)
    files_list = png_files.join(' ')
    command = "convert #{files_list} -append #{output_file}"
    
    LOGGER.debug "Running ImageMagick: #{command}"
    
    result = system(command)
    
    if result && File.exist?(output_file)
      LOGGER.debug "ImageMagick merge successful"
      true
    else
      LOGGER.error "ImageMagick merge failed"
      false
    end
  end
  
  def self.merge_json_metadata(sprite_files, png_files)
    merged_json = {}
    current_y = 0
    
    sprite_files.each_with_index do |sprite_file, index|
      json_data = sprite_file[:json_data]
      png_file = png_files[index]
      
      png_height = get_png_height(png_file)
      
      json_data.each do |icon_name, icon_data|
        merged_json[icon_name] = {
          'width' => icon_data['width'],
          'height' => icon_data['height'],
          'pixelRatio' => icon_data['pixelRatio'],
          'x' => icon_data['x'],
          'y' => icon_data['y'] + current_y
        }
      end
      
      current_y += png_height
    end
    
    merged_json
  end
  
  def self.get_png_height(png_file)
    result = `identify -format "%h" #{png_file}`.strip.to_i
    result > 0 ? result : 0
  rescue => e
    LOGGER.error "Failed to get PNG height for #{png_file}: #{e.message}"
    0
  end
  
  def self.copy_single_sprite(sprite_file, mix_id)
    source_png = sprite_file[:png_file]
    source_json = sprite_file[:json_file]
    
    FileUtils.cp(source_png, File.join(output_dir, "#{mix_id}_sprite.png"))
    FileUtils.cp(source_json, File.join(output_dir, "#{mix_id}_sprite.json"))
    
    LOGGER.debug "Copied single sprite from #{sprite_file[:dir]}"
    true
  end
  
  def self.log_no_sprites(mix_id)
    LOGGER.warn "No sprite directories found for #{mix_id}"
    nil
  end
end
