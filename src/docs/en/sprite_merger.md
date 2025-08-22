# Sprite Merger Component

## Overview

The `SpriteMerger` class handles merging of sprite assets from multiple Mapbox styles into unified sprite sets. It processes both regular and high-DPI (@2x) sprite images and their corresponding JSON metadata, creating combined sprite resources that can be used by the mixed styles.

## Core Functionality

### Sprite Merging Process

The sprite merging process involves several key steps:

1. **Sprite Collection**: Scans and collects sprite files from multiple source styles
2. **Sprite Deduplication**: Removes duplicate sprites based on PNG file and JSON metadata comparison
3. **Image Merging**: Combines PNG sprite images using ImageMagick montage command
4. **Metadata Merging**: Merges JSON sprite metadata with coordinate adjustments
5. **Output Generation**: Creates unified sprite sets for both regular and @2x versions

### Sprite Deduplication

The component automatically detects and removes duplicate sprites, preventing redundancy in final styles:

```ruby
def deduplicate_sprites(sprite_files)
  return [] if sprite_files.empty?
  return sprite_files if sprite_files.length == 1
  
  # Group sprites by hash
  sprite_groups = group_sprites_by_hash(sprite_files)
  
  # Log duplicate information
  if sprite_groups.length < sprite_files.length
    sprite_groups.each_with_index do |group, index|
      if group.length > 1
        sprite_names = group.map { |s| File.basename(s[:dir]) }
        LOGGER.info "Found duplicate sprites in group #{index + 1}: #{sprite_names.join(', ')}"
      end
    end
  end
  
  # Select one sprite from each group
  sprite_groups.map { |group| group.first }
end
```

**Deduplication Process**:
- **Hash Computation**: MD5 hash is computed for each sprite based on PNG file and JSON metadata
- **Grouping**: Sprites are grouped by hash to identify duplicates
- **Logging**: Information about found duplicates is logged
- **Representative Selection**: One sprite is selected from each duplicate group

**Sprite Hash Computation**:
```ruby
def compute_sprite_hash(sprite)
  png_hash = Digest::MD5.file(sprite[:png_file]).hexdigest
  json_hash = Digest::MD5.hexdigest(sprite[:json_data].to_json)
  
  "#{png_hash}_#{json_hash}"
end
```

**Sprite Identity Check**:
```ruby
def sprites_identical?(sprite1, sprite2)
  return false unless sprite1 && sprite2
  
  # Compare PNG files
  png_identical = FileUtils.compare_file(sprite1[:png_file], sprite2[:png_file])
  return false unless png_identical
  
  # Compare JSON metadata
  json_identical = sprite1[:json_data] == sprite2[:json_data]
  
  png_identical && json_identical
end
```

**Deduplication Benefits**:
- **Size Reduction**: Excluding duplicate sprites reduces final file sizes
- **Performance Improvement**: Fewer sprites to process and load
- **Memory Optimization**: Reduced memory consumption during map rendering
- **Debugging Simplification**: Cleaner logs and merge process reports

### Key Methods

#### `merge_all_sprites`
Processes all configured sprite sets in the system by iterating through the configuration and calling individual merge operations.

#### `merge_sprites_for_mix(mix_id)`
Merges sprites for a specific style mix:
- Collects regular and @2x sprites from all source styles
- Performs sprite deduplication to remove duplicates
- Merges each sprite set independently
- Returns success status for monitoring

#### `merge_sprite_set(sprite_files, mix_id, high_dpi)`
Merges a set of sprites (regular or @2x):
- Validates sprite files exist and are accessible
- Performs image merging using ImageMagick
- Updates metadata coordinates for proper positioning

### Sprite Collection

The component collects sprite files from multiple sources by scanning the sprites directory:

```ruby
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
```

**Process Details**:
- Uses glob patterns to find sprite directories for the specific mix
- Filters for @2x directories when processing high-DPI sprites
- Loads sprite data (PNG and JSON) from each directory
- Returns compacted array of valid sprite data

### Image Merging

Uses ImageMagick for sprite image merging with vertical stacking:

```ruby
def merge_png_files(png_files, output_png)
  return false if png_files.empty?
  
  if png_files.length == 1
    FileUtils.cp(png_files.first, output_png)
    return true
  end
  
  # Use ImageMagick montage for merging
  cmd = "montage #{png_files.join(' ')} -tile 1x -geometry +0+0 #{output_png}"
  system(cmd)
end
```

**Merging Strategy**:
- **Single Sprite**: Direct file copying for efficiency
- **Multiple Sprites**: Vertical stacking using ImageMagick montage
- **Tile Layout**: 1xN grid for vertical arrangement
- **Geometry**: +0+0 spacing between sprites

### Metadata Merging

Merges JSON sprite metadata with coordinate adjustments for proper icon positioning:

```ruby
def merge_json_metadata(sprite_files, png_files)
  merged_json = {}
  current_y = 0
  
  sprite_files.each_with_index do |sprite_file, index|
    sprite_file[:json_data].each do |icon_name, icon_data|
      # Adjust Y coordinates for vertical stacking
      adjusted_data = icon_data.dup
      adjusted_data['y'] = icon_data['y'] + current_y
      merged_json[icon_name] = adjusted_data
    end
    
    # Update Y offset for next sprite
    current_y += get_sprite_height(png_files[index])
  end
  
  merged_json
end
```

**Coordinate Adjustment Process**:
- **Y-Offset Calculation**: Accumulates height of previous sprites
- **Icon Positioning**: Adjusts each icon's Y coordinate by the offset
- **Metadata Preservation**: Maintains original X coordinates and dimensions
- **Icon Naming**: Preserves original icon names to avoid conflicts

### Output Structure

Generates unified sprite sets in the sprite directory:

```
sprite/
  mix_style1_sprite.png      # Merged regular sprites
  mix_style1_sprite.json     # Merged metadata for regular sprites
  mix_style1_sprite@2x.png   # Merged @2x sprites (high-DPI)
  mix_style1_sprite@2x.json  # Merged metadata for @2x sprites
```

**File Organization**:
- **Naming Convention**: Uses mix_id with `_sprite` suffix
- **Resolution Support**: Separate files for regular and @2x versions
- **Metadata Alignment**: JSON files correspond to PNG files
- **Directory Structure**: All merged sprites in single sprite/ directory

### High DPI Support

Handles both regular and @2x sprite versions with independent processing and automatic fallback generation:

**Regular Sprites**:
- Standard resolution (1x) sprite images
- Base coordinate system
- Standard icon dimensions

**@2x Sprites**:
- High-DPI resolution (2x) sprite images
- Scaled coordinate system
- Doubled icon dimensions for retina displays

**Processing Differences**:
- Separate collection patterns for each resolution
- Independent merging processes
- Coordinate scaling considerations for @2x sprites
- Different output file naming conventions

**Fallback Generation**:
When @2x sprites are missing or incomplete for source styles, the system automatically generates them from regular sprites:
- Uses ImageMagick to scale regular sprite images by 2x
- Scales JSON metadata coordinates and dimensions proportionally
- Creates scaled sprites directly in existing @2x directories
- Maintains visual consistency across different display densities

### Single Sprite Handling

Optimizes performance for scenarios with only one source sprite:

**Optimization Strategy**:
- **Direct Copying**: Uses FileUtils.cp instead of ImageMagick
- **Metadata Preservation**: No coordinate adjustments needed
- **Performance Gain**: Avoids unnecessary image processing
- **Resource Efficiency**: Minimal memory and CPU usage

### Error Handling

Comprehensive error handling for various failure scenarios:

**File System Errors**:
- Missing sprite file validation
- Directory access permission checks
- Disk space availability verification

**Image Processing Errors**:
- ImageMagick command failure handling
- Invalid PNG file format detection
- Corrupted image file recovery

**Metadata Errors**:
- JSON parsing error recovery
- Invalid metadata structure handling
- Missing required fields validation

**Graceful Degradation**:
- Continues processing on individual sprite failures
- Logs errors for debugging
- Returns partial results when possible

### Integration

Seamlessly integrates with other system components:

**StyleDownloader Integration**:
- Works with downloaded sprite sources
- Processes sprites from multiple style sources
- Handles sprite files organized by StyleDownloader

**StyleMixer Integration**:
- Provides merged sprite assets for style mixing
- Updates sprite references in mixed styles
- Ensures sprite availability for final styles

**Configuration Integration**:
- Uses configuration from `styles_config.yaml`
- Processes sprites based on style mix definitions
- Supports custom mix identifiers

### Performance Considerations

Optimized for efficient sprite processing:

**Memory Management**:
- Streams large sprite files instead of loading entirely into memory
- Processes sprites sequentially to minimize memory usage
- Cleans up temporary files after processing

**Processing Optimization**:
- Efficient file copying for single sprites
- ImageMagick optimization for large sprite sets
- Parallel processing support for multiple mixes

**Resource Efficiency**:
- Minimal disk I/O operations
- Optimized image compression
- Efficient metadata processing algorithms
