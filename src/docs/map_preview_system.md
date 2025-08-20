# Map Preview System Documentation

## Overview

The Map Preview System is a sophisticated web-based interface for visualizing and interacting with Mapbox/MapLibre styles. It provides real-time filtering capabilities, performance monitoring, and a dual-mode interface for both layer-based and filter-based control.

## Architecture

### Core Components

1. **Map Container** (`map.slim`)
   - Main interactive map interface
   - Dual-layer system (base map + style map)
   - Real-time performance monitoring
   - Two-level filtering system

2. **Layout System** (`map_layout.slim`)
   - Dark theme UI with IntelliJ-inspired styling
   - Responsive controls and panels
   - Performance overlay system

### Technology Stack

- **Frontend**: MapLibre GL JS 5.0.1
- **Styling**: Custom CSS with dark theme
- **Templating**: Slim template engine
- **Backend**: Ruby/Sinatra (for style serving)

## Two-Level Filtering System

### Architecture

The filtering system is implemented as a separate `Filters` class (`src/public/js/filters.js`) that encapsulates all filtering logic and provides a clean API for filter management.

### Class Structure

```javascript
class Filters {
  constructor(options) {
    this.map = options.map;           // MapLibre map instance
    this.container = options.container; // DOM container for buttons
    this.element_template = options.element_template; // Template for elements
    this.group_template = options.group_template;     // Template for groups
    
    this.filterStates = {};
    this.subFilterStatesBeforeGroupToggle = {};
    this.currentStyle = null;
    this.currentMode = 'filters';
    this.isUpdating = false;
  }

  init() { /* Initialize filters from map */ }
  setMode(mode) { /* Switch between filter/layer modes */ }
  applyFilterMode() { /* Apply filter mode logic */ }
  applyFilter(filterId, isActive) { /* Apply specific filter */ }
  toggleAllFilters() { /* Toggle all filters */ }
  toggleFilterGroup(filterId) { /* Toggle filter group */ }
  toggleSubFilter(groupId, subFilterId) { /* Toggle sub-filter */ }
  createFilterButtons() { /* Create UI buttons */ }
  updateFilterButtons() { /* Update button states */ }
}
```

### Integration

The `Filters` class is integrated into the main map interface:

```javascript
// In map.slim
filters = new Filters({
  map: map,
  container: '#filter-buttons',
  element_template: (title) => `<div class="element">${title}</div>`,
  group_template: (title) => `<div class="group">${title}</div>`
});
filters.init();
```

### Level 1: Simple Layer Filtering

**Purpose**: Basic visibility control for layers without complex filtering logic.

**Implementation**:
```javascript
applyLevel1Filter(filterId, isActive, filterConfig) {
  this.currentStyle.layers.forEach(layer => {
    if (!layer.metadata?.filter_id) return;
    
    const matchingFilter = filterConfig.find(filter => filter.id === layer.metadata.filter_id);
    if (matchingFilter) {
      if (filterConfig.length > 1) {
        // Sub-filter logic
        const subFilterKey = `${filterId}_${layer.metadata.filter_id}`;
        const subFilterActive = this.filterStates[subFilterKey];
        const visibility = (isActive && subFilterActive) ? 'visible' : 'none';
        this.map.getLayer(layer.id) && this.map.setLayoutProperty(layer.id, 'visibility', visibility);
      } else {
        // Simple on/off
        this.map.getLayer(layer.id) && this.map.setLayoutProperty(layer.id, 'visibility', isActive ? 'visible' : 'none');
      }
    }
  });
}
```

**Example Style Configuration**:
```json
{
  "metadata": {
    "filters": {
      "weather": [
        {
          "id": "temperature",
          "name": "Temperature"
        },
        {
          "id": "precipitation", 
          "name": "Precipitation"
        }
      ]
    }
  },
  "layers": [
    {
      "id": "temp-layer",
      "metadata": {
        "filter_id": "temperature"
      }
    },
    {
      "id": "precip-layer", 
      "metadata": {
        "filter_id": "precipitation"
      }
    }
  ]
}
```

### Level 2: Advanced Expression Filtering

**Purpose**: Complex filtering using Mapbox expressions for data-driven styling.

### How the System Distinguishes Between Filter Levels

The system automatically determines which filtering level to use based on the presence of `filter` expressions in the metadata:

```javascript
applyFilter(filterId, isActive) {
  if (this.currentMode !== 'filters' || !this.currentStyle?.metadata?.filters) return;
  
  const filterConfig = this.currentStyle.metadata.filters[filterId];
  if (!filterConfig) return;

  // Key detection logic: check if any filter has a 'filter' property
  const hasMapboxFilters = filterConfig.some(filter => filter.filter);
  
  // Route to appropriate filtering level
  hasMapboxFilters ? this.applyLevel2Filter(filterId, isActive, filterConfig) : this.applyLevel1Filter(filterId, isActive, filterConfig);
}
```

**Detection Logic**:
- **Level 1**: When `filterConfig.some(filter => filter.filter)` returns `false`
  - No `filter` expressions in metadata
  - Simple visibility control only
- **Level 2**: When `filterConfig.some(filter => filter.filter)` returns `true`
  - Contains `filter` expressions in metadata
  - Advanced expression-based filtering

**Example - Level 1 Detection**:
```json
{
  "metadata": {
    "filters": {
      "weather": [
        {
          "id": "temperature",
          "name": "Temperature"
          // No 'filter' property = Level 1
        },
        {
          "id": "precipitation", 
          "name": "Precipitation"
          // No 'filter' property = Level 1
        }
      ]
    }
  }
}
```

**Example - Level 2 Detection**:
```json
{
  "metadata": {
    "filters": {
      "airspace": [
        {
          "id": "controlled",
          "name": "Controlled Airspace",
          "filter": ["==", ["get", "class"], "controlled"]  // Has 'filter' = Level 2
        },
        {
          "id": "restricted",
          "name": "Restricted Areas", 
          "filter": ["==", ["get", "class"], "restricted"]  // Has 'filter' = Level 2
        }
      ]
    }
  }
}
```

**Implementation**:
```javascript
applyLevel2Filter(filterId, isActive, filterConfig) {
  const subFiltersWithExpr = filterConfig.filter(f => !!f.filter);
  const generalLayers = this.currentStyle.layers.filter(layer => layer.metadata?.filter_id === filterId);
  
  if (!isActive) {
    // Disable all layers
    generalLayers.forEach(layer => {
      if (this.map.getLayer(layer.id)) {
        this.map.setLayoutProperty(layer.id, 'visibility', 'none');
        this.map.setFilter(layer.id, null);
      }
    });
    return;
  }

  // Apply expression filters
  const activeWithExpr = subFiltersWithExpr.filter(f => this.filterStates[`${filterId}_${f.id}`] !== false);
  
  if (activeWithExpr.length === 1) {
    // Single filter - apply directly
    const expr = activeWithExpr[0].filter;
    generalLayers.forEach(layer => {
      if (this.map.getLayer(layer.id)) {
        this.map.setLayoutProperty(layer.id, 'visibility', 'visible');
        this.map.setFilter(layer.id, expr);
      }
    });
  } else if (activeWithExpr.length > 1) {
    // Multiple filters - combine with OR logic
    const exprs = activeWithExpr.map(f => f.filter);
    const combined = ['any', ...exprs];
    generalLayers.forEach(layer => {
      if (this.map.getLayer(layer.id)) {
        this.map.setLayoutProperty(layer.id, 'visibility', 'visible');
        this.map.setFilter(layer.id, combined);
      }
    });
  }
}
```

**Example Style Configuration**:
```json
{
  "metadata": {
    "filters": {
      "airspace": [
        {
          "id": "controlled",
          "name": "Controlled Airspace",
          "filter": ["==", ["get", "class"], "controlled"]
        },
        {
          "id": "restricted",
          "name": "Restricted Areas", 
          "filter": ["==", ["get", "class"], "restricted"]
        },
        {
          "id": "danger",
          "name": "Danger Areas",
          "filter": ["==", ["get", "class"], "danger"]
        }
      ]
    }
  },
  "layers": [
    {
      "id": "airspace-layer",
      "metadata": {
        "filter_id": "airspace"
      }
    }
  ]
}
```

## Dual Mode Interface

### Filters Mode

**Purpose**: Control layers through metadata-defined filters with sub-filter support.

**Features**:
- Group-based filtering
- Sub-filter toggles
- State preservation
- Complex expression support

**UI Structure**:
```html
<div class="filter-group">
  <button class="filter-group-button">Weather</button>
  <div class="filter-sub-buttons">
    <button class="filter-sub-button">Temperature</button>
    <button class="filter-sub-button">Precipitation</button>
  </div>
</div>
```

### Layers Mode

**Purpose**: Direct layer visibility control without filter logic.

**Features**:
- Individual layer toggles
- Bulk operations (toggle all)
- Simple on/off states

**Implementation**:
```javascript
const toggleLayer = (layerId) => {
  if (currentMode !== 'layers') return;
  layerStates[layerId] = !layerStates[layerId];
  
  if (map.getLayer(layerId)) {
    map.setLayoutProperty(layerId, 'visibility', layerStates[layerId] ? 'visible' : 'none');
  }
  updateLayerButtons();
};
```

## Architecture Benefits

### Separation of Concerns

The `Filters` class architecture provides several key benefits:

1. **Modularity**: Filter logic is completely separated from map initialization and UI management
2. **Reusability**: The `Filters` class can be easily integrated into other projects
3. **Testability**: Filter logic can be tested independently
4. **Maintainability**: Changes to filtering logic don't affect other parts of the system

### Clean API

The `Filters` class provides a clean, object-oriented API:

```javascript
// Initialize filters
const filters = new Filters(options);
filters.init();

// Switch modes
filters.setMode('filters');  // or 'layers'

// Control filters
filters.toggleAllFilters();
filters.toggleFilterGroup('weather');
filters.toggleSubFilter('weather', 'temperature');
```

### State Management

The class manages its own state internally:

```javascript
class Filters {
  constructor(options) {
    this.filterStates = {};                    // Individual filter states
    this.subFilterStatesBeforeGroupToggle = {}; // State preservation
    this.currentStyle = null;                  // Current style reference
    this.currentMode = 'filters';              // Current mode
    this.isUpdating = false;                   // Update flag
  }
}
```

### Integration Points

The class integrates seamlessly with the system:

- **Map Integration**: Direct access to MapLibre map instance for style retrieval
- **UI Integration**: Automatic button creation and state updates
- **Style Integration**: Automatic parsing of map styles and filter extraction
- **Event Integration**: Handles all filter-related user interactions

## Performance Monitoring

### Real-time Metrics

The system provides comprehensive performance monitoring:

```javascript
const updatePerformanceMetrics = () => {
  // FPS calculation
  const fps = Math.round((frameCount * 1000) / (now - lastFpsTime));
  
  // Memory usage
  const memoryMB = Math.round(performance.memory.usedJSHeapSize / 1024 / 1024);
  
  // Active layers count
  let activeLayers = 0;
  currentStyle.layers.forEach(layer => {
    if (map.getLayer(layer.id)) {
      const visibility = map.getLayoutProperty(layer.id, 'visibility');
      if (visibility === 'visible') activeLayers++;
    }
  });
  
  // Zoom level
  const zoom = map.getZoom();
};
```

### Metrics Display

- **FPS**: Real-time frame rate with color coding
- **Frame Time**: Average frame rendering time
- **Memory Usage**: JavaScript heap usage
- **Active Layers**: Count of visible layers
- **Zoom Level**: Current map zoom
- **Tiles Loaded**: Number of loaded tile sources

## Map Synchronization

### Dual Map System

The system uses two synchronized maps:

```javascript
const syncMaps = (map, map_base) => {
  map.on('move', () => {
    if (!map_base || map_base._isDestroyed) return;
    
    const center = map.getCenter();
    const zoom = map.getZoom();
    const bearing = map.getBearing();
    const pitch = map.getPitch();
    
    map_base.jumpTo({ center, zoom, bearing, pitch });
    map_base.triggerRepaint(); 
    map_base.resize();
  });
};
```

**Purpose**:
- Base map provides context
- Style map shows filtered data
- Synchronized navigation
- Toggle-able base map visibility

## State Management

### Filter States

```javascript
let filterStates = {};
let layerStates = {};
let subFilterStatesBeforeGroupToggle = {};
```

**State Structure**:
- `filterStates[filterId]`: Boolean state for main filters
- `filterStates[filterId_subFilterId]`: Boolean state for sub-filters
- `layerStates[layerId]`: Boolean state for individual layers
- `subFilterStatesBeforeGroupToggle`: Temporary storage for group toggle operations

### State Persistence

States are maintained during:
- Mode switching
- Filter toggles
- Layer operations
- Map interactions

## Error Handling

### Graceful Degradation

```javascript
// Map creation with error handling
const createMap = (container, style) => {
  if (!container || !style) return null;
  
  try {
    return new maplibregl.Map({
      container, style,
      center: [35.15, 47.41], zoom: 2, 
      attributionControl: false, validateStyle: false
    });
  } catch (e) {
    console.error('Failed to create map:', e);
    return null;
  }
};

// Error logging
map.on('error', (e) => { 
  console.error('[MapLibre ERROR]', e?.error || e); 
});
```

### Resource Loading

```javascript
const checkStyleResources = (style) => {
  if (!style) return;
  
  totalResources = 0; 
  resourcesLoaded = 0;
  const promises = [];
  
  if (style.sprite) {
    totalResources += 2;
    promises.push(
      Promise.all([
        fetch(style.sprite + '.json').catch(() => {}),
        fetch(style.sprite + '.png').catch(() => {})
      ]).then(() => { resourcesLoaded += 2; updateLoadingProgress(); })
    );
  }
  
  if (style.glyphs) {
    totalResources += 1;
    promises.push(Promise.resolve().then(() => { 
      resourcesLoaded++; 
      updateLoadingProgress(); 
    }));
  }
};
```

## Usage Examples

### Basic Implementation

```html
<!-- HTML Structure -->
<div id="map-container">
  <div id="map_base" class="map-layer"></div>
  <div id="map" class="map-layer" data-style-url="/styles/example-style"></div>
  
  <div class="layer-controls">
    <div class="mode-switcher">
      <button class="mode-button active" onclick="switchMode(this, 'filters')">Filters</button>
      <button class="mode-button" onclick="switchMode(this, 'layers')">Layers</button>
    </div>
    
    <div id="filters-panel" class="control-panel active">
      <button onclick="toggleAllFilters()">Toggle All Filters</button>
      <div id="filter-buttons"></div>
    </div>
    
    <div id="layers-panel" class="control-panel">
      <button onclick="toggleAllLayers()">Toggle All Layers</button>
      <div id="layer-buttons"></div>
    </div>
  </div>
</div>
```

### Style Configuration

```json
{
  "version": 8,
  "name": "Example Style",
  "metadata": {
    "filters": {
      "transport": [
        {
          "id": "roads",
          "name": "Roads",
          "filter": ["==", ["get", "type"], "road"]
        },
        {
          "id": "railways",
          "name": "Railways", 
          "filter": ["==", ["get", "type"], "railway"]
        }
      ],
      "poi": [
        {
          "id": "restaurants",
          "name": "Restaurants"
        },
        {
          "id": "shops",
          "name": "Shops"
        }
      ]
    },
    "locale": {
      "en": {
        "transport": "Transport",
        "roads": "Roads",
        "railways": "Railways",
        "poi": "Points of Interest",
        "restaurants": "Restaurants",
        "shops": "Shops"
      }
    }
  },
  "layers": [
    {
      "id": "transport-layer",
      "metadata": {
        "filter_id": "transport"
      }
    },
    {
      "id": "restaurant-layer",
      "metadata": {
        "filter_id": "restaurants"
      }
    },
    {
      "id": "shop-layer", 
      "metadata": {
        "filter_id": "shops"
      }
    }
  ]
}
```

## Best Practices

### Style Design

1. **Consistent Metadata**: Use consistent filter_id naming
2. **Logical Grouping**: Group related layers under meaningful filter names
3. **Expression Optimization**: Use efficient Mapbox expressions
4. **Localization**: Provide locale data for UI labels

### Performance

1. **Layer Optimization**: Minimize layer count
2. **Filter Efficiency**: Use simple filters when possible
3. **Resource Management**: Monitor memory usage
4. **Error Handling**: Implement graceful fallbacks

### User Experience

1. **Intuitive Controls**: Clear button labels and grouping
2. **State Feedback**: Visual indication of active states
3. **Performance Monitoring**: Real-time metrics display
4. **Responsive Design**: Adapt to different screen sizes

## Troubleshooting

### Common Issues

1. **Layers Not Visible**: Check filter states and layer metadata
2. **Performance Issues**: Monitor FPS and memory usage
3. **Filter Not Working**: Verify expression syntax and data properties
4. **State Loss**: Check state management during mode switches

### Debug Tools

- Browser console for error messages
- Performance panel for metrics
- Network tab for resource loading
- MapLibre debug mode for detailed logging
