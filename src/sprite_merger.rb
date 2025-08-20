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
    
    regular_sprites = collect_sprite_files(mix_id)
    high_dpi_sprites = collect_sprite_files(mix_id, true)
    
    merge_sprite_set(regular_sprites, mix_id, false)
    merge_sprite_set(high_dpi_sprites, mix_id, true)
    
    regular_sprites.any? || high_dpi_sprites.any?
  end

  def merge_sprite_set(sprite_files, mix_id, high_dpi)
    return if sprite_files.empty?
    
    success = merge_sprites(sprite_files, mix_id, high_dpi)
    suffix = high_dpi ? "@2x" : ""
    
    if success
      LOGGER.info "Successfully merged #{sprite_files.length} sprites#{suffix} for #{mix_id}"
    else
      LOGGER.error "Failed to merge sprites#{suffix} for #{mix_id}"
    end
  end

  private

  def prepare_sprite_directory
    FileUtils.rm_rf(@output_dir) if Dir.exist?(@output_dir)
    FileUtils.mkdir_p(@output_dir)
  end

  def collect_sprite_files(mix_id, high_dpi = false)
    if high_dpi
      pattern = "#{@sprites_dir}/#{mix_id}_*_@2x"
      sprite_dirs = Dir.glob(pattern).select { |d| Dir.exist?(d) }
    else
      pattern = "#{@sprites_dir}/#{mix_id}_*"
      sprite_dirs = Dir.glob(pattern).select { |d| Dir.exist?(d) && !d.end_with?('_@2x') }
    end
    
    sprite_dirs.map { |dir| load_sprite_data(dir) }.compact
  end

  def load_sprite_data(dir)
    png_file = File.join(dir, 'sprite.png')
    json_file = File.join(dir, 'sprite.json')
    
    return unless File.exist?(png_file) && File.exist?(json_file)
    
    json_data = JSON.parse(File.read(json_file))
    LOGGER.debug "Found sprite from #{dir}"
    { png_file: png_file, json_file: json_file, json_data: json_data, dir: dir }
  rescue => e
    LOGGER.error "Failed to load sprite from #{dir}: #{e.message}"
    nil
  end

  def merge_sprites(sprite_files, mix_id, high_dpi = false)
    return false if sprite_files.empty?
    
    suffix = high_dpi ? "@2x" : ""
    output_png = File.join(@output_dir, "#{mix_id}_sprite#{suffix}.png")
    output_json = File.join(@output_dir, "#{mix_id}_sprite#{suffix}.json")
    
    return copy_single_sprite(sprite_files.first, mix_id, high_dpi) if sprite_files.length == 1
    
    png_files = sprite_files.map { |sf| sf[:png_file] }
    return false unless merge_png_files(png_files, output_png)
    
    merged_json = merge_json_metadata(sprite_files, png_files)
    File.write(output_json, JSON.pretty_generate(merged_json))
    
    LOGGER.debug "Saved merged sprite#{suffix} using ImageMagick"
    true
  rescue => e
    LOGGER.error "Error merging sprites#{suffix}: #{e.message}"
    false
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

  def copy_single_sprite(sprite_file, mix_id, high_dpi = false)
    FileUtils.mkdir_p(@output_dir)
    suffix = high_dpi ? "@2x" : ""
    
    FileUtils.cp(sprite_file[:png_file], File.join(@output_dir, "#{mix_id}_sprite#{suffix}.png"))
    FileUtils.cp(sprite_file[:json_file], File.join(@output_dir, "#{mix_id}_sprite#{suffix}.json"))
    
    LOGGER.debug "Copied single sprite#{suffix} from #{sprite_file[:dir]}"
    true
  end
end
