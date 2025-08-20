# Style Downloader Component

## Overview

The `StyleDownloader` class handles downloading and processing of Mapbox styles from remote sources. It manages the complete lifecycle of style acquisition, including authentication, resource extraction, and asset organization for multiple style sources.

## Core Functionality

### Download Process

The style downloading process follows a comprehensive workflow:

1. **Directory Preparation**: Creates necessary directory structure for organized storage
2. **Style Download**: Downloads JSON style files from remote URLs with authentication support
3. **Resource Extraction**: Extracts sprite and font references from style JSON
4. **Asset Download**: Downloads sprites and font glyphs from remote sources
5. **File Organization**: Organizes downloaded assets by style with proper naming conventions

### Key Methods

#### `download_all`
Downloads all configured styles in the system by iterating through the configuration and processing each style mix.

#### `download_style(mix_id)`
Downloads a specific style configuration identified by mix_id, including all its source styles and associated resources.

#### `process_mix_style(mix_id, mix_config)`
Processes a complete style mix configuration:
- Downloads all source styles for the mix
- Extracts sprite and font references from each style
- Downloads all required assets (sprites, fonts)
- Organizes files with proper naming and structure

### Style Download

Downloads JSON style files with comprehensive authentication support:

```ruby
def download_source_style(source_config, mix_id, index)
  source_url = source_config.is_a?(Hash) ? source_config['url'] : source_config
  auth_config = source_config.is_a?(Hash) ? source_config['auth'] : nil
  
  headers = {}
  if auth_config
    credentials = Base64.strict_encode64("#{auth_config['username']}:#{auth_config['password']}")
    headers['Authorization'] = "Basic #{credentials}"
  end
  
  resp = Faraday.get(source_url, headers: headers)
  raise "Failed to fetch #{source_url}" unless resp.success?
  
  style_json = JSON.parse(resp.body)
  # Process and save style...
end
```

**Download Features**:
- **URL Support**: Handles both simple URLs and complex configurations
- **Authentication**: Basic Auth support for protected style sources
- **Error Handling**: Comprehensive error checking and reporting
- **JSON Validation**: Ensures downloaded content is valid JSON

### Resource Extraction

#### Sprite Extraction
Extracts sprite URLs from style JSON and downloads both regular and @2x versions:

**Extraction Process**:
- **URL Detection**: Identifies sprite URLs in style JSON
- **Version Support**: Handles both regular and @2x sprite variants
- **Metadata Download**: Downloads both PNG images and JSON metadata
- **File Organization**: Organizes sprites by style and resolution

#### Font Extraction
Extracts font stack references and downloads glyph ranges:

**Font Processing**:
- **Font Stack Detection**: Identifies font stacks in style configuration
- **Glyph Range Calculation**: Determines required glyph ranges
- **Range Download**: Downloads glyph files for each range (0-255, 256-511, etc.)
- **Font Organization**: Organizes fonts by font stack name

### File Organization

Organizes downloaded files with a structured hierarchy:

```
raw_styles/
  mix_style1_source1_1.json
  mix_style1_source2_2.json

sprites/
  mix_style1_source1_1/
    sprite.png
    sprite.json
  mix_style1_source1_1_@2x/
    sprite.png
    sprite.json

fonts/
  fontstack_name/
    0-255.pbf
    256-511.pbf
    512-767.pbf
    ...
```

**Organization Strategy**:
- **Style Separation**: Each source style gets its own directory
- **Resource Categorization**: Sprites and fonts in separate directories
- **Naming Convention**: Uses mix_id and source index for unique identification
- **Resolution Support**: Separate directories for regular and @2x sprites

### Authentication Support

Supports Basic Authentication for protected style sources with flexible configuration:

```yaml
styles:
  mix_style1:
    sources:
      - url: "https://example.com/style.json"
        auth:
          username: "user"
          password: "pass"
        prefix: "custom_prefix"
```

**Authentication Features**:
- **Basic Auth**: Standard username/password authentication
- **Flexible Configuration**: Supports both simple URLs and complex configs
- **Secure Handling**: Proper credential encoding and transmission
- **Error Recovery**: Handles authentication failures gracefully

### Parallel Processing

Uses parallel processing for efficient downloads of multiple resources:

```ruby
def download_fonts(fontstacks, glyphs_urls)
  Parallel.each(fontstacks, in_threads: 4) do |fontstack|
    download_font_glyphs(fontstack, glyphs_urls)
  end
end
```

**Parallel Processing Benefits**:
- **Concurrent Downloads**: Multiple resources downloaded simultaneously
- **Thread Management**: Configurable thread count for optimal performance
- **Resource Efficiency**: Reduces total download time significantly
- **Error Isolation**: Individual download failures don't affect others

### Error Handling

Comprehensive error handling for various network and file system scenarios:

**Network Error Handling**:
- **Connection Failures**: Retries with exponential backoff
- **Timeout Handling**: Configurable timeout values
- **HTTP Error Codes**: Proper handling of 4xx and 5xx responses
- **DNS Resolution**: Handles domain resolution failures

**File System Error Handling**:
- **Permission Issues**: Checks and handles file permission errors
- **Disk Space**: Validates available disk space before downloads
- **Directory Creation**: Handles directory creation failures
- **File Corruption**: Validates downloaded file integrity

**Authentication Error Handling**:
- **Invalid Credentials**: Handles authentication failures
- **Expired Tokens**: Manages token expiration scenarios
- **Access Denied**: Handles authorization failures

**Graceful Degradation**:
- **Partial Downloads**: Continues processing when some resources fail
- **Error Logging**: Comprehensive logging for debugging
- **Fallback Mechanisms**: Alternative approaches when primary methods fail

### Integration

Seamlessly integrates with other system components:

**Configuration Integration**:
- **YAML Configuration**: Reads from `styles_config.yaml`
- **Style Definitions**: Processes style mix configurations
- **Source Management**: Handles multiple source styles per mix
- **Prefix Support**: Supports custom prefixes for style identification

**StyleMixer Integration**:
- **File Preparation**: Prepares raw style files for mixing
- **Resource Availability**: Ensures all required resources are available
- **Metadata Preservation**: Maintains style metadata for mixing process
- **Error Propagation**: Reports download status to mixing process

**SpriteMerger Integration**:
- **Sprite Organization**: Provides organized sprite files for merging
- **Metadata Files**: Supplies sprite JSON metadata for coordinate processing
- **Resolution Support**: Provides both regular and @2x sprite variants
- **File Structure**: Maintains consistent file organization

**System Integration**:
- **Directory Structure**: Creates and maintains required directories
- **File Naming**: Uses consistent naming conventions across components
- **Resource Management**: Manages disk space and file organization
- **Progress Tracking**: Provides download progress information
