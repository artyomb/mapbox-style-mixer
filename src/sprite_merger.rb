require 'json'
require 'fileutils'

class SpriteMerger
  def initialize(config = nil)
    @config = config || $config
    @sprites_dir = File.expand_path('sprites', __dir__)
    @output_dir = File.expand_path('sprite', __dir__)
  end

  def merge_all_sprites
    LOGGER.info "Starting merging of all sprites"
    prepare_sprite_directory
    
    @config['styles'].each do |mix_id, mix_config|
      merge_sprites_for_mix(mix_id)
    rescue => e
      LOGGER.error "Error merging sprites for #{mix_id}: #{e.message}"
    end
    
    LOGGER.info "Sprite merging completed"
  end

  def merge_sprites_for_mix(mix_id)
    LOGGER.info "Starting sprite merging for #{mix_id}"
    
    sprite_files = collect_sprite_files(mix_id)
    if sprite_files.empty?
      LOGGER.warn "No sprite directories found for #{mix_id}"
      return false
    end
    
    success = merge_sprites(sprite_files, mix_id)
    
    if success
      LOGGER.info "Successfully merged #{sprite_files.length} sprites for #{mix_id}"
      true
    else
      LOGGER.error "Failed to merge sprites for #{mix_id}"
      false
    end
  end

  private

  def prepare_sprite_directory
    FileUtils.rm_rf(@output_dir) if Dir.exist?(@output_dir)
    FileUtils.mkdir_p(@output_dir)
  end

  def collect_sprite_files(mix_id)
    sprite_dirs = Dir.glob("#{@sprites_dir}/#{mix_id}_*").select { |d| Dir.exist?(d) }
    return [] if sprite_dirs.empty?
    
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

  def merge_sprites(sprite_files, mix_id)
    return false if sprite_files.empty?
    
    begin
      return copy_single_sprite(sprite_files.first, mix_id) if sprite_files.length == 1
      
      output_png = File.join(@output_dir, "#{mix_id}_sprite.png")
      output_json = File.join(@output_dir, "#{mix_id}_sprite.json")
      
      png_files = sprite_files.map { |sf| sf[:png_file] }
      
      return false unless merge_png_files(png_files, output_png)
      
      merged_json = merge_json_metadata(sprite_files, png_files)
      File.write(output_json, JSON.pretty_generate(merged_json))
      
      LOGGER.debug "Saved merged sprite using ImageMagick"
      true
    rescue => e
      LOGGER.error "Error merging sprites: #{e.message}"
      false
    end
  end

  def merge_png_files(png_files, output_file)
    FileUtils.mkdir_p(File.dirname(output_file))
    
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

  def merge_json_metadata(sprite_files, png_files)
    merged_json = {}
    current_y = 0
    
    sprite_files.each_with_index do |sprite_file, index|
      json_data = sprite_file[:json_data]
      png_height = get_png_height(png_files[index])
      
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

  def get_png_height(png_file)
    result = `identify -format "%h" #{png_file}`.strip.to_i
    result > 0 ? result : 0
  rescue => e
    LOGGER.error "Failed to get PNG height for #{png_file}: #{e.message}"
    0
  end

  def copy_single_sprite(sprite_file, mix_id)
    FileUtils.mkdir_p(@output_dir)
    FileUtils.cp(sprite_file[:png_file], File.join(@output_dir, "#{mix_id}_sprite.png"))
    FileUtils.cp(sprite_file[:json_file], File.join(@output_dir, "#{mix_id}_sprite.json"))
    
    LOGGER.debug "Copied single sprite from #{sprite_file[:dir]}"
    true
  end
end
