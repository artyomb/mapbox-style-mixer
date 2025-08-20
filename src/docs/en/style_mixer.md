# Style Mixer Component

## Overview

The `StyleMixer` class is responsible for combining multiple Mapbox styles into a single mixed style configuration. It handles the complex process of merging sources, layers, and metadata while ensuring proper prefix management to avoid naming conflicts between different style sources.

## Core Functionality

### Style Mixing Process

The style mixing process involves several sophisticated steps:

1. **Base Structure Creation**: Creates initial style structure with proper Mapbox version and metadata
2. **Source Loading**: Loads raw style files from disk with validation and error handling
3. **Prefix Generation**: Generates unique prefixes for each source style to prevent conflicts
4. **Resource Merging**: Merges sources, layers, and metadata with proper transformations
5. **Sprite Integration**: Integrates merged sprite assets with correct URL references
6. **Output Generation**: Saves final mixed style to JSON with proper formatting

### Key Methods

#### `mix_all_styles`
Processes all configured styles in the system by iterating through the configuration and calling individual mixing operations.

#### `mix_styles(mix_id, mix_config)`
Mixes a specific style configuration:
- Creates base structure with proper Mapbox version
- Loads and validates all source styles
- Generates unique prefixes for conflict avoidance
- Merges all resources (sources, layers, metadata)
- Integrates sprite assets with correct references
- Saves final mixed style to output directory

### Prefix Generation

Generates unique prefixes for each source style to avoid naming conflicts:

```ruby
def generate_prefixes(source_styles)
  used_prefixes = Set.new
  
  source_styles.map.with_index do |style, index|
    base_prefix = style['_config_prefix'] || style['id'] || 
                  style['name']&.downcase&.gsub(/\s+/, '_') || "style_#{index + 1}"
    clean_prefix = base_prefix.gsub(/[^a-zA-Z0-9_]/, '_').squeeze('_')
    prefix = resolve_conflicts(clean_prefix, used_prefixes)
    used_prefixes.add(prefix)
    prefix
  end
end
```

**Prefix Generation Strategy**:
- **Source Priority**: Uses `_config_prefix` if available, then `id`, then `name`
- **Fallback Naming**: Generates `style_#{index + 1}` if no identifier available
- **Conflict Resolution**: Ensures unique prefixes across all source styles
- **Character Cleaning**: Removes invalid characters and normalizes naming

### Resource Merging

#### Sources Merging
Combines tile sources from multiple styles with prefixed names:

**Merging Process**:
- **Source Collection**: Gathers all tile sources from source styles
- **Prefix Application**: Applies unique prefixes to source names
- **URL Preservation**: Maintains original tile URLs and parameters
- **Type Handling**: Preserves source types (vector, raster, geojson, etc.)

**Example Transformation**:
```json
// Original source
{
  "source1": {
    "type": "vector",
    "url": "https://example.com/tiles"
  }
}

// After prefixing
{
  "weather_source1": {
    "type": "vector", 
    "url": "https://example.com/tiles"
  }
}
```

#### Layers Merging
Merges layer definitions with updated source references and metadata:

**Layer Processing**:
- **Source Reference Updates**: Updates layer source references to prefixed names
- **Metadata Preservation**: Maintains layer metadata and properties
- **Order Preservation**: Maintains original layer ordering
- **Filter Integration**: Preserves layer filters and expressions

**Layer Transformation Example**:
```json
// Original layer
{
  "id": "temperature-layer",
  "source": "source1",
  "type": "fill",
  "paint": { "fill-color": "#ff0000" }
}

// After merging
{
  "id": "weather_temperature-layer", 
  "source": "weather_source1",
  "type": "fill",
  "paint": { "fill-color": "#ff0000" }
}
```

#### Metadata Merging
Combines filter configurations and localization data:

**Metadata Processing**:
- **Filter Aggregation**: Combines filter configurations from all sources
- **Localization Merging**: Merges locale data for multiple languages
- **Conflict Resolution**: Handles duplicate filter names and locale keys
- **Structure Preservation**: Maintains metadata structure integrity

**Metadata Example**:
```json
{
  "metadata": {
    "filters": {
      "weather": [
        { "id": "temperature", "name": "Temperature" },
        { "id": "precipitation", "name": "Precipitation" }
      ],
      "transport": [
        { "id": "roads", "name": "Roads" }
      ]
    },
    "locale": {
      "en": {
        "weather": "Weather",
        "temperature": "Temperature"
      },
      "ru": {
        "weather": "Погода", 
        "temperature": "Температура"
      }
    }
  }
}
```

### Output Structure

Generated mixed style includes comprehensive Mapbox style specification:

**Style Components**:
- **Version**: Mapbox style version (8) for compatibility
- **Name**: Mixed style name from configuration
- **Sources**: Merged tile sources with prefixed names
- **Layers**: Combined layer definitions with updated references
- **Metadata**: Merged filters and locale data
- **Sprite**: Reference to merged sprite assets
- **Glyphs**: Font glyph endpoint for text rendering

**Complete Style Example**:
```json
{
  "version": 8,
  "name": "Weather and Transport Style",
  "sources": {
    "weather_source1": {
      "type": "vector",
      "url": "https://example.com/weather-tiles"
    },
    "transport_source2": {
      "type": "vector", 
      "url": "https://example.com/transport-tiles"
    }
  },
  "layers": [
    {
      "id": "weather_temperature-layer",
      "source": "weather_source1",
      "type": "fill",
      "paint": { "fill-color": "#ff0000" }
    },
    {
      "id": "transport_roads-layer", 
      "source": "transport_source2",
      "type": "line",
      "paint": { "line-color": "#000000" }
    }
  ],
  "sprite": "/sprite/mix_style1_sprite",
  "glyphs": "/fonts/{fontstack}/{range}",
  "metadata": {
    "filters": {
      "weather": [
        { "id": "temperature", "name": "Temperature" }
      ],
      "transport": [
        { "id": "roads", "name": "Roads" }
      ]
    }
  }
}
```

### Integration

Seamlessly integrates with other system components:

**StyleDownloader Integration**:
- **File Input**: Reads raw style files prepared by StyleDownloader
- **Resource Availability**: Ensures all required resources are available
- **Error Handling**: Handles missing files and corrupted data
- **Progress Tracking**: Reports mixing progress and status

**SpriteMerger Integration**:
- **Sprite References**: Updates sprite URLs to point to merged assets
- **Metadata Alignment**: Ensures sprite metadata matches merged sprites
- **Resolution Support**: Handles both regular and @2x sprite references
- **URL Generation**: Creates correct sprite URLs for mixed styles

**Configuration Integration**:
- **YAML Processing**: Reads from `styles_config.yaml`
- **Style Definitions**: Processes style mix configurations
- **Source Management**: Handles multiple source styles per mix
- **Output Organization**: Saves mixed styles to `mixed_styles/` directory

### Error Handling

Comprehensive error handling for various mixing scenarios:

**File System Errors**:
- **Missing Files**: Graceful handling of missing source style files
- **Corrupted Data**: Validation and recovery from corrupted JSON
- **Permission Issues**: Handles file permission and access errors
- **Disk Space**: Validates available disk space before writing

**Data Validation Errors**:
- **Invalid JSON**: Handles malformed JSON in source styles
- **Missing Required Fields**: Validates required Mapbox style fields
- **Type Mismatches**: Handles incorrect data types in style definitions
- **Reference Errors**: Validates source and layer references

**Conflict Resolution**:
- **Duplicate Names**: Resolves naming conflicts between source styles
- **Prefix Collisions**: Ensures unique prefix generation
- **Layer Conflicts**: Handles duplicate layer IDs and names
- **Source Conflicts**: Resolves source naming conflicts

**Graceful Degradation**:
- **Partial Mixing**: Continues processing when some sources fail
- **Error Logging**: Comprehensive logging for debugging
- **Fallback Values**: Uses default values when data is missing
- **Progress Reporting**: Reports mixing progress and error status
