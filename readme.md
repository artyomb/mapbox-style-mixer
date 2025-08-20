# Mapbox Style Mixer

A specialized service for combining and mixing Mapbox styles with support for sprites, fonts, and filters. The service downloads multiple source styles, merges them into unified styles, and serves them through a REST API.

[![Ruby](https://img.shields.io/badge/ruby-3.4+-red.svg)](https://ruby-lang.org)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](docker/)
[![Tests](https://img.shields.io/badge/tests-passing-green.svg)](src/spec/)

## Features

- **Style Mixing**: Combine multiple Mapbox styles into unified styles
- **Sprite Merging**: Automatic merging of sprite images and metadata
- **Font Management**: Download and cache font files with range support
- **Filter System**: Support for style filters with localization
- **Map Preview System**: Interactive web-based map interface with real-time filtering
- **Progress Tracking**: Real-time initialization progress monitoring
- **REST API**: Complete API for style serving and management
- **Docker Support**: Containerized deployment with volume mounting
- **Testing**: Comprehensive test coverage for all components

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

### Configuration Parameters

- `styles`: Root object containing all style definitions
- `id`: Unique identifier for the mixed style
- `name`: Human-readable name for the style
- `sources`: Array of URLs to source Mapbox styles

## API Reference

### Core Endpoints

| Endpoint | Method | Description | Response |
|----------|--------|-------------|----------|
| `/` | GET | Main interface with style list | HTML |
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

## Architecture

### Core Components

- **StyleDownloader**: Downloads source styles, sprites, and fonts
- **StyleMixer**: Combines multiple styles with prefix management
- **SpriteMerger**: Merges sprite images and metadata
- **Map Preview System**: Interactive web interface with filtering capabilities
- **Sinatra App**: REST API and web interface

### Data Flow

1. **Initialization**: Service downloads all source styles on startup
2. **Style Processing**: Each source style is processed and cached
3. **Mixing**: Styles are combined with unique prefixes
4. **Resource Merging**: Sprites and fonts are merged
5. **Serving**: Mixed styles served through REST API

### File Structure

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
│   ├── api/               # API tests
│   ├── services/          # Service tests
│   └── integration/       # Integration tests
├── mixed_styles/          # Generated mixed styles
├── sprite/                # Merged sprite files
├── sprites/               # Source sprite files
├── raw_styles/            # Downloaded source styles
├── fonts/                 # Font files
└── docs/                  # Documentation
    └── map_preview_system.md  # Map preview system documentation
```

## Development

### Prerequisites

- Ruby 3.4+
- Bundler
- Docker (optional)

### Map Preview System

The service includes an interactive map preview system accessible at `/map`. This system provides:

- **Dual Mode Interface**: Switch between filter-based and layer-based control
- **Real-time Filtering**: Two-level filtering system with Mapbox expressions
- **Performance Monitoring**: Real-time FPS, memory usage, and layer statistics
- **Synchronized Maps**: Base map and style map with synchronized navigation

For detailed documentation, see [Map Preview System Documentation](src/docs/map_preview_system.md).

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

The project includes comprehensive test coverage:

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

### Docker Development

```bash
# Build image
docker build -t mapbox-style-mixer .

# Run with volume mounting
docker run --rm \
  -v $(pwd)/src:/app \
  -v $(pwd)/styles_config.yaml:/configs/styles_config.yaml \
  -p 7000:7000 \
  mapbox-style-mixer
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

### Logs

Service logs are available through standard output:

```bash
# View logs
docker logs mapbox-style-mixer

# Follow logs
docker logs -f mapbox-style-mixer
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Run the test suite (`bundle exec rspec`)
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and questions:
- Create an issue on GitHub
- Check the troubleshooting section
- Review the test examples in `src/spec/`