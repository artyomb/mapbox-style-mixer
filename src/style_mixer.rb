require 'json'
require 'fileutils'
require 'yaml'
require 'set'

class StyleMixer
  def initialize(config = nil)
    @config = config || $config
    @raw_dir = File.expand_path('raw_styles', __dir__)
    @mixed_dir = File.expand_path('mixed_styles', __dir__)
  end

  def mix_all_styles
    FileUtils.rm_rf(@mixed_dir) if Dir.exist?(@mixed_dir)
    FileUtils.mkdir_p(@mixed_dir)
    
    LOGGER.info "Starting mixing of all styles"
    
    @config['styles'].each do |mix_id, mix_config|
      mix_styles(mix_id, mix_config)
    rescue => e
      LOGGER.error "Error mixing #{mix_id}: #{e.message}"
    end
    
    LOGGER.info "Style mixing completed"
  end

  def mix_styles(mix_id, mix_config)
    LOGGER.info "Starting style mixing: #{mix_id}"
    
    mixed_style = create_base_structure(mix_id, mix_config)
    source_styles = load_source_styles(mix_id)
    
    if source_styles.empty?
      LOGGER.warn "No source styles found for #{mix_id}"
      return mixed_style
    end
    
    style_prefixes = generate_prefixes(source_styles)
    
    source_styles.each_with_index do |style_data, index|
      prefix = style_prefixes[index]
      %w[sources metadata layers].each { |type| send("merge_#{type}", mixed_style, style_data, prefix) }
    end
    
    require_relative 'sprite_merger'
    sprite_merger = SpriteMerger.new(@config)
    sprite_result = sprite_merger.merge_sprites_for_mix(mix_id)
    
    mixed_style['sprite'] = sprite_result ? "/sprite/#{mix_id}_sprite" : nil
    mixed_style['glyphs'] = "/fonts/{fontstack}/{range}.pbf"
    
    FileUtils.mkdir_p(@mixed_dir)
    filename = File.join(@mixed_dir, "#{mix_id}.json")
    File.write(filename, JSON.pretty_generate(mixed_style))
    LOGGER.debug "Saved mixed style: #{filename}"
    
    LOGGER.info "Mixed style completed: #{mixed_style['sources'].length} sources, #{mixed_style['layers'].length} layers, #{mixed_style.dig('metadata', 'filters')&.length || 0} filters"
    
    mixed_style
  end

  private

  def create_base_structure(mix_id, mix_config)
    {
      'version' => 8,
      'name' => mix_config['name'] || "Mixed Style: #{mix_id}",
      'sprite' => nil,
      'glyphs' => nil,
      'metadata' => { 'filters' => {}, 'locale' => { 'ru' => {}, 'en-US' => {} } },
      'sources' => {},
      'layers' => [],
      'id' => mix_id
    }
  end

  def load_source_styles(mix_id)
    files = Dir.glob("#{@raw_dir}/#{mix_id}_*.json")
    files.sort_by! { |file| File.basename(file).match(/_(\d+)\.json$/)[1].to_i }
    LOGGER.debug "Loading #{files.length} source styles for #{mix_id}"
    files.map { |file| JSON.parse(File.read(file)) }
  end

  def generate_prefixes(source_styles)
    used_prefixes = Set.new
    
    source_styles.map.with_index do |style, index|
      base_prefix = style['_config_prefix'] || style['id'] || style['name']&.downcase&.gsub(/\s+/, '_') || "style_#{index + 1}"
      clean_prefix = base_prefix.gsub(/[^a-zA-Z0-9_]/, '_').squeeze('_')
      prefix = resolve_conflicts(clean_prefix, used_prefixes)
      used_prefixes.add(prefix)
      prefix
    end
  end

  def resolve_conflicts(prefix, used_prefixes)
    return prefix unless used_prefixes.include?(prefix)
    (1..Float::INFINITY).lazy.map { |i| "#{prefix}_#{i}" }.find { |p| !used_prefixes.include?(p) }
  end

  def merge_sources(mixed_style, source_style, prefix)
    return unless source_style['sources']
    source_style['sources'].each { |name, config| mixed_style['sources']["#{prefix}_#{name}"] = config.dup }
  end

  def merge_layers(mixed_style, source_style, prefix)
    return unless source_style['layers']
    
    source_style['layers'].each do |layer|
      new_layer = deep_dup(layer)
      new_layer['id'] = "#{prefix}_#{layer['id']}"
      new_layer['source'] = "#{prefix}_#{layer['source']}" if layer['source']
      
      if layer.dig('layout', 'text-font')
        new_layer['layout']['text-font'] = layer['layout']['text-font'].map { |font| "#{prefix}/#{font}" }
      end
      
      new_layer['metadata'] ||= {}
      
      if layer.dig('metadata', 'filter_id')
        if layer['metadata']['filter_id'] == prefix
          new_layer['metadata']['filter_id'] = prefix
        else
          new_layer['metadata']['filter_id'] = "#{prefix}_#{layer['metadata']['filter_id']}"
        end
      else
        new_layer['metadata']['filter_id'] = prefix
      end
      
      mixed_style['layers'] << new_layer
    end
  end

  def merge_metadata(mixed_style, source_style, prefix)
    return unless source_style['metadata']
    
    merge_filters(mixed_style, source_style, prefix)
    merge_locale(mixed_style, source_style, prefix)
    merge_other_metadata(mixed_style, source_style)
  end

  def merge_filters(mixed_style, source_style, prefix)
    if source_style.dig('metadata', 'filters')
      source_style['metadata']['filters'].each do |filter_group, filters|
        prefixed_filters = filters.map do |filter|
          filter.dup.tap do |new_filter|
            new_filter['id'] = "#{prefix}_#{filter['id']}" if filter['id']
            new_filter['group_id'] = "#{prefix}_#{filter['group_id']}" if filter['group_id']
          end
        end
        
        mixed_style['metadata']['filters']["#{prefix}_#{filter_group}"] = prefixed_filters
      end
    else
      create_style_filter(mixed_style, source_style, prefix)
    end
  end

  def create_style_filter(mixed_style, source_style, prefix)
    style_name = prefix.to_s
      .gsub(/([a-z0-9])([A-Z])/, '\\1 \\2')
      .tr('_-', ' ')
      .squeeze(' ')
      .strip
      .split
      .map!(&:capitalize)
      .join(' ')
    
    mixed_style['metadata']['filters'][prefix] = [
      {
        'id' => prefix,
        'name' => style_name
      }
    ]
    
    mixed_style['metadata']['locale']['en-US'][prefix] = style_name
  end

  def merge_locale(mixed_style, source_style, prefix)
    return unless source_style.dig('metadata', 'locale')
    
    %w[ru en-US].each do |lang|
      next unless source_style['metadata']['locale'][lang]
      source_style['metadata']['locale'][lang].each { |key, value| mixed_style['metadata']['locale'][lang]["#{prefix}_#{key}"] = value }
    end
  end

  def merge_other_metadata(mixed_style, source_style)
    %w[feature_inspector feature_geometry find_in_point popup_template hover_template maputnik:renderer].each do |field|
      mixed_style['metadata'][field] = source_style['metadata'][field] if source_style['metadata'][field]
    end
  end

  def deep_dup(obj)
    case obj
    when Hash then obj.transform_values { |v| deep_dup(v) }
    when Array then obj.map { |v| deep_dup(v) }
    else obj.dup rescue obj
    end
  end
end

 