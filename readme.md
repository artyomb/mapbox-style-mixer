# Mapbox Style Mixer

A specialized service for combining and mixing Mapbox styles with support for sprites, fonts, and filters. The service downloads multiple source styles, merges them into unified styles, and serves them through a REST API.

[![Ruby](https://img.shields.io/badge/ruby-3.4+-red.svg)](https://ruby-lang.org)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](docker/)
[![Tests](https://img.shields.io/badge/tests-passing-green.svg)](src/spec/)
[![Русский](https://img.shields.io/badge/русский-документация-orange.svg)](src/docs/ru/README.md)

## Key Features

- **Style Mixing**: Combine multiple Mapbox styles into unified styles with automatic prefix management
- **Sprite Merging**: Automatic merging of sprite images and metadata using ImageMagick with fallback generation for high-DPI sprites
- **Font Management**: Download and cache font files with range support (0-255, 256-511, etc.)
- **Advanced Filtering**: Two-level filtering system with Mapbox expressions and real-time layer control
- **Interactive Preview**: Web-based map interface with dual-mode controls (filters/layers), performance monitoring, and source style navigation
- **REST API**: Complete API for style serving with authentication support
- **Docker Ready**: Containerized deployment with volume mounting for configuration

## Architecture Overview

The service consists of several key components:

- **[Style Mixer](src/docs/en/style_mixer.md)** - Combines multiple Mapbox styles with prefix management
- **[Style Downloader](src/docs/en/style_downloader.md)** - Downloads source styles and resources with authentication support
- **[Sprite Merger](src/docs/en/sprite_merger.md)** - Merges sprite assets using ImageMagick
- **[Map Preview System](src/docs/en/map_preview_system.md)** - Advanced filtering and layer management

## Quick Start

### Using Docker

```bash
# Create configuration file
cat > styles_config.yaml << EOF
styles:
  my_style:
    id: 'my_combined_style'
    name: "My Combined Style"
    sources:
      - https://example.com/style1.json
      - https://example.com/style2.json
EOF

# Run with Docker
docker run --rm \
  -v $(pwd)/styles_config.yaml:/configs/styles_config.yaml \
  -p 7000:7000 \
  mapbox-style-mixer

# Access the service
open http://localhost:7000
```

### Local Development

```bash
# Clone repository
git clone https://github.com/user/mapbox-style-mixer.git
cd mapbox-style-mixer

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Start development server
bundle exec rackup
```

## Configuration

The service uses a YAML configuration file to define style combinations:

```yaml
# styles_config.yaml
styles:
  weather_location:
    id: 'weather_location_1'
    name: "Weather and Location Style"
    sources:
      - https://example.com/styles/weather/weather
      - https://example.com/styles/location/location

  weather_location_tz:
    id: 'weather_location_tz_2'
    name: "Weather, Location and Timezones Style"
    sources:
      - https://example.com/styles/weather/weather
      - https://example.com/styles/location/location
      - https://example.com/styles/weather/timezones
```

## API Reference

### Core Endpoints

| Endpoint | Method | Description | Response |
|----------|--------|-------------|----------|
| `/` | GET | Main interface with style list and source navigation | HTML |
| `/status` | GET | Service initialization status | JSON |
| `/styles` | GET | List all available styles | JSON |
| `/styles/:id` | GET | Get mixed style JSON | JSON |
| `/refresh` | GET | Reload and remix all styles | Redirect |
| `/map` | GET | Interactive map preview interface | HTML |

### Resource Endpoints

| Endpoint | Method | Description | Response |
|----------|--------|-------------|----------|
| `/sprite/:id.png` | GET | Get sprite image | PNG |
| `/sprite/:id.json` | GET | Get sprite metadata | JSON |
| `/fonts/*/:range.pbf` | GET | Get font file | Binary |

### Response Examples

**GET /styles**
```json
{
  "available_styles": [
    {
      "id": "weather_location_1",
      "name": "Weather and Location Style",
      "endpoint": "/styles/weather_location_1",
      "sources_count": 2
    }
  ]
}
```

**GET /status**
```json
{
  "state": "ready",
  "progress": 100,
  "message": "Ready"
}
```

## File Structure

```
src/
├── config.ru              # Main Sinatra application
├── style_downloader.rb    # Style downloading service
├── style_mixer.rb         # Style mixing logic
├── sprite_merger.rb       # Sprite merging service
├── configs/
│   └── styles_config.yaml # Configuration file
├── views/                 # Web interface templates
│   ├── index.slim         # Main page
│   ├── map.slim           # Map preview interface
│   ├── map_layout.slim    # Map layout template
│   └── layout.slim        # Layout template
├── public/                # Static assets
│   └── js/                # JavaScript files
│       └── filters.js     # Filter system implementation
├── spec/                  # Test suite
├── mixed_styles/          # Generated mixed styles
├── sprite/                # Merged sprite files
├── sprites/               # Source sprite files
├── raw_styles/            # Downloaded source styles
├── fonts/                 # Font files
└── docs/                  # Documentation
    ├── en/                # English documentation
    └── ru/                # Russian documentation
```

## Development

### Prerequisites

- Ruby 3.4+
- Bundler
- Docker (optional)

### Setup

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Start development server
bundle exec rackup -p 7000

# Run with Docker
docker-compose up
```

### Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test categories
bundle exec rspec spec/api/
bundle exec rspec spec/services/
bundle exec rspec spec/integration/

# Run with coverage
COVERAGE=true bundle exec rspec
```

## Deployment

### Docker Compose

```yaml
# docker-compose.yml
services:
  mapbox_style_mixer:
    image: mapbox-style-mixer
    ports:
      - "7000:7000"
    environment:
      - CONFIG_PATH=/configs/styles_config.yaml
    volumes:
      - ./styles_config.yaml:/configs/styles_config.yaml
```

### Environment Variables

- `CONFIG_PATH`: Path to configuration file (default: `configs/styles_config.yaml`)
- `RACK_ENV`: Environment mode (development/production)

## Troubleshooting

### Common Issues

**Styles not loading**
- Check source URLs are accessible
- Verify YAML configuration syntax
- Check service logs for download errors

**Sprites not displaying**
- Ensure ImageMagick is installed for sprite merging
- Check sprite file permissions
- Verify sprite JSON metadata format

**Fonts not loading**
- Check font file accessibility
- Verify font range format (0-255, 256-511, etc.)
- Ensure font directory permissions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.