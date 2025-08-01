require 'json'
require 'fileutils'
require 'yaml'
require 'set'

module StyleMixer
  def self.mix_styles(mix_id, mix_config)
    LOGGER.info "Starting style mixing: #{mix_id}"
    
    mixed_style = create_base_structure(mix_id, mix_config)
    source_styles = load_source_styles(mix_id)
    
    return log_no_styles(mixed_style, mix_id) if source_styles.empty?
    
    style_prefixes = generate_prefixes(source_styles)
    
    source_styles.each_with_index do |style_data, index|
      prefix = style_prefixes[index]
      %w[sources layers metadata].each { |type| send("merge_#{type}", mixed_style, style_data, prefix) }
    end
    
    require_relative 'sprite_merger'
    SpriteMerger.merge_sprites_for_mix(mix_id)
    
    update_resource_urls(mixed_style, mix_id)
    save_mixed_style(mixed_style, mix_id)
    log_success(mixed_style)
    
    mixed_style
  end
  
  def self.mix_all_styles
    config = load_config
    prepare_mixed_styles_directory
    
    LOGGER.info "Starting mixing of all styles"
    
    config['styles'].each do |mix_id, mix_config|
      mix_styles(mix_id, mix_config)
    rescue => e
      LOGGER.error "Error mixing #{mix_id}: #{e.message}"
    end
    
    LOGGER.info "Style mixing completed"
  end
  
  private
  
  def self.create_base_structure(mix_id, mix_config)
    {
      'version' => 8,
      'id' => mix_id,
      'name' => mix_config['name'] || "Mixed Style: #{mix_id}",
      'sources' => {},
      'layers' => [],
      'metadata' => { 'filters' => {}, 'locale' => { 'ru' => {}, 'en-US' => {} } }
    }
  end
  
  def self.load_source_styles(mix_id)
    raw_dir = File.expand_path('raw_styles', __dir__)
    
    files = Dir.glob("#{raw_dir}/#{mix_id}_*.json").sort
    LOGGER.debug "Loading #{files.length} source styles for #{mix_id}"
    
    files.map { |file| JSON.parse(File.read(file)) }
  end
  
  def self.generate_prefixes(source_styles)
    used_prefixes = Set.new
    
    source_styles.map.with_index do |style, index|
      base_prefix = extract_base_prefix(style, index)
      clean_prefix = sanitize_prefix(base_prefix)
      prefix = resolve_conflicts(clean_prefix, used_prefixes)
      used_prefixes.add(prefix)
      prefix
    end
  end
  
  def self.extract_base_prefix(style, index)
    style['id'] || style['name']&.downcase&.gsub(/\s+/, '_') || "style_#{index + 1}"
  end
  
  def self.sanitize_prefix(prefix)
    prefix.gsub(/[^a-zA-Z0-9_]/, '_').squeeze('_')
  end
  
  def self.resolve_conflicts(prefix, used_prefixes)
    return prefix unless used_prefixes.include?(prefix)
    
    (1..Float::INFINITY).lazy.map { |i| "#{prefix}_#{i}" }.find { |p| !used_prefixes.include?(p) }
  end
  
  def self.merge_sources(mixed_style, source_style, prefix)
    return unless source_style['sources']
    
    source_style['sources'].each do |name, config|
      mixed_style['sources']["#{prefix}_#{name}"] = config.dup
    end
  end
  
  def self.merge_layers(mixed_style, source_style, prefix)
    return unless source_style['layers']
    
    source_style['layers'].each do |layer|
      new_layer = deep_dup(layer)
      new_layer['id'] = "#{prefix}_#{layer['id']}"
      new_layer['source'] = "#{prefix}_#{layer['source']}" if layer['source']
      
      if layer.dig('layout', 'text-font')
        new_layer['layout']['text-font'] = layer['layout']['text-font'].map do |font|
          "#{prefix}/#{font}"
        end
      end
      
      if layer.dig('metadata', 'filter_id')
        new_layer['metadata'] = layer['metadata'].dup
        new_layer['metadata']['filter_id'] = "#{prefix}_#{layer['metadata']['filter_id']}"
      end
      
      mixed_style['layers'] << new_layer
    end
  end
  
  def self.merge_metadata(mixed_style, source_style, prefix)
    return unless source_style['metadata']
    
    merge_filters(mixed_style, source_style, prefix)
    merge_locale(mixed_style, source_style, prefix)
    merge_other_metadata(mixed_style, source_style)
  end
  
  def self.merge_filters(mixed_style, source_style, prefix)
    return unless source_style.dig('metadata', 'filters')
    
    source_style['metadata']['filters'].each do |filter_group, filters|
      prefixed_filters = filters.map do |filter|
        filter.dup.tap do |new_filter|
          new_filter['id'] = "#{prefix}_#{filter['id']}" if filter['id']
          new_filter['group_id'] = "#{prefix}_#{filter['group_id']}" if filter['group_id']
        end
      end
      
      mixed_style['metadata']['filters']["#{prefix}_#{filter_group}"] = prefixed_filters
    end
  end
  
  def self.merge_locale(mixed_style, source_style, prefix)
    return unless source_style.dig('metadata', 'locale')
    
    %w[ru en-US].each do |lang|
      next unless source_style['metadata']['locale'][lang]
      
      source_style['metadata']['locale'][lang].each do |key, value|
        mixed_style['metadata']['locale'][lang]["#{prefix}_#{key}"] = value
      end
    end
  end
  
  def self.merge_other_metadata(mixed_style, source_style)
    %w[feature_inspector feature_geometry find_in_point popup_template hover_template maputnik:renderer].each do |field|
      mixed_style['metadata'][field] = source_style['metadata'][field] if source_style['metadata'][field]
    end
  end
  
  def self.update_resource_urls(mixed_style, mix_id)
    mixed_style['sprite'] = "/sprite/#{mix_id}_sprite"
    mixed_style['glyphs'] = "/fonts/{fontstack}/{range}.pbf"
  end
  
  def self.save_mixed_style(mixed_style, mix_id)
    mixed_dir = File.expand_path('mixed_styles', __dir__)
    FileUtils.mkdir_p(mixed_dir)
    
    filename = File.join(mixed_dir, "#{mix_id}.json")
    File.write(filename, JSON.pretty_generate(mixed_style))
    
    LOGGER.debug "Saved mixed style: #{filename}"
  end
  
  def self.prepare_mixed_styles_directory
    mixed_dir = File.expand_path('mixed_styles', __dir__)
    
    FileUtils.rm_rf(mixed_dir) if Dir.exist?(mixed_dir)
    FileUtils.mkdir_p(mixed_dir)
  end
  
  def self.load_config
    $config
  end
  
  def self.deep_dup(obj)
    case obj
    when Hash then obj.transform_values { |v| deep_dup(v) }
    when Array then obj.map { |v| deep_dup(v) }
    else obj.dup rescue obj
    end
  end
  
  def self.log_no_styles(mixed_style, mix_id)
    LOGGER.warn "No source styles found for #{mix_id}"
    mixed_style
  end
  
  def self.log_success(mixed_style)
    LOGGER.info "Mixed style completed: #{mixed_style['sources'].length} sources, #{mixed_style['layers'].length} layers, #{mixed_style.dig('metadata', 'filters')&.length || 0} filters"
  end
end

 