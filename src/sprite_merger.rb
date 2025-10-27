require 'json'
require 'fileutils'
require 'digest'

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
    
    unique_regular_sprites = deduplicate_sprites(regular_sprites)
    unique_high_dpi_sprites = deduplicate_sprites(high_dpi_sprites)
    
    LOGGER.info "Found #{regular_sprites.length} regular sprites, #{unique_regular_sprites.length} unique"
    LOGGER.info "Found #{high_dpi_sprites.length} @2x sprites, #{unique_high_dpi_sprites.length} unique"
    
    merge_sprite_set(unique_regular_sprites, mix_id, false)
    
    if unique_high_dpi_sprites.length == unique_regular_sprites.length
      merge_sprite_set(unique_high_dpi_sprites, mix_id, true)
    elsif unique_regular_sprites.any?
      create_fallback_high_dpi_sprites(mix_id, unique_regular_sprites, unique_high_dpi_sprites)
    end
    
    regular_sprites.any? || high_dpi_sprites.any?
  end

  def deduplicate_sprites(sprite_files)
    return sprite_files if sprite_files.length <= 1
    
    sprite_groups = group_sprites_by_hash(sprite_files)
    log_duplicates(sprite_groups, sprite_files.length) if sprite_groups.length < sprite_files.length
    sprite_groups.map(&:first)
  end

  def group_sprites_by_hash(sprite_files)
    sprite_files.group_by { |sprite| compute_sprite_hash(sprite) }.values
  end

  def compute_sprite_hash(sprite)
    png_hash = Digest::MD5.file(sprite[:png_file]).hexdigest
    json_hash = Digest::MD5.hexdigest(sprite[:json_data].to_json)
    "#{png_hash}_#{json_hash}"
  end

  def sprites_identical?(sprite1, sprite2)
    return false unless sprite1 && sprite2
    
    FileUtils.compare_file(sprite1[:png_file], sprite2[:png_file]) && 
      sprite1[:json_data] == sprite2[:json_data]
  end

  private

  def log_duplicates(sprite_groups, total_count)
    sprite_groups.each_with_index do |group, index|
      next unless group.length > 1
      sprite_names = group.map { |s| File.basename(s[:dir]) }
      LOGGER.info "Found duplicate sprites in group #{index + 1}: #{sprite_names.join(', ')}"
    end
  end

  def create_fallback_high_dpi_sprites(mix_id, regular_sprites, existing_high_dpi_sprites = [])
    LOGGER.info "Creating fallback @2x sprites for #{mix_id}"
    
    all_high_dpi_dirs = Dir.glob("#{@sprites_dir}/#{mix_id}_*_@2x").select { |d| Dir.exist?(d) }
    
    scaled_sprites = regular_sprites.map do |sprite|
      sprite_name = File.basename(sprite[:dir])
      high_dpi_dir = all_high_dpi_dirs.find { |d| d.end_with?("#{sprite_name}_@2x") }
      
      if high_dpi_dir
        existing_high_dpi_sprites.find { |s| s[:dir] == high_dpi_dir } || 
          create_scaled_sprite_in_dir(sprite, high_dpi_dir)
      else
        create_scaled_sprite_in_dir(sprite, "#{sprite[:dir]}_@2x_temp")
      end
    end.compact
    
    merge_sprite_set(scaled_sprites, mix_id, true) if scaled_sprites.any?
  end

  def create_scaled_sprite_in_dir(sprite_data, high_dpi_dir)
    png_file = File.join(high_dpi_dir, 'sprite.png')
    json_file = File.join(high_dpi_dir, 'sprite.json')
    
    File.write(png_file, scale_png_file(sprite_data[:png_file], 2.0))
    File.write(json_file, JSON.pretty_generate(scale_json_metadata(sprite_data[:json_data], 2.0)))
    
    { png_file: png_file, json_file: json_file, json_data: scale_json_metadata(sprite_data[:json_data], 2.0), dir: high_dpi_dir }
  rescue => e
    LOGGER.error "Failed to create scaled sprite in #{high_dpi_dir}: #{e.message}"
    nil
  end

  def scale_png_file(png_file, scale_factor)
    output_file = "#{png_file}_scaled"
    system("convert #{png_file} -scale #{scale_factor * 100}% #{output_file}")
    File.read(output_file).tap { File.delete(output_file) }
  rescue => e
    LOGGER.error "Failed to scale PNG #{png_file}: #{e.message}"
    File.read(png_file)
  end

  def scale_json_metadata(json_data, scale_factor)
    json_data.transform_values do |icon_data|
      icon_data.dup.tap do |scaled_icon|
        %w[width height x y].each { |key| scaled_icon[key] = (icon_data[key] * scale_factor).round }
        scaled_icon['pixelRatio'] = (icon_data['pixelRatio'] || 1) * scale_factor
      end
    end
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
    command = "convert #{files_list} -append +repage #{output_file}"
    
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
