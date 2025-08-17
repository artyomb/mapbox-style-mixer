# Документация системы предварительного просмотра карт

## Обзор

Система предварительного просмотра карт - это сложный веб-интерфейс для визуализации и взаимодействия с Mapbox/MapLibre стилями. Она предоставляет возможности фильтрации в реальном времени, мониторинг производительности и двухрежимный интерфейс для управления как на уровне слоев, так и на уровне фильтров.

## Архитектура

### Основные компоненты

1. **Контейнер карты** (`map.slim`)
   - Основной интерактивный интерфейс карты
   - Двухслойная система (базовая карта + карта стиля)
   - Мониторинг производительности в реальном времени
   - Двухуровневая система фильтрации

2. **Система макета** (`map_layout.slim`)
   - Темная тема UI в стиле IntelliJ
   - Адаптивные элементы управления и панели
   - Система оверлея производительности

### Технологический стек

- **Фронтенд**: MapLibre GL JS 5.0.1
- **Стилизация**: Пользовательский CSS с темной темой
- **Шаблонизация**: Slim template engine
- **Бэкенд**: Ruby/Sinatra (для обслуживания стилей)

## Двухуровневая система фильтрации

### Концепция

Система реализует сложный двухуровневый механизм фильтрации, который может обрабатывать как простую видимость слоев, так и сложные Mapbox-выражения.

### Уровень 1: Простая фильтрация слоев

**Назначение**: Базовое управление видимостью слоев без сложной логики фильтрации.

**Реализация**:
```javascript
const applyLevel1Filter = (filterId, isActive, filterConfig) => {
  currentStyle.layers.forEach(layer => {
    if (!layer.metadata?.filter_id) return;
    
    const matchingFilter = filterConfig.find(filter => filter.id === layer.metadata.filter_id);
    if (matchingFilter) {
      if (filterConfig.length > 1) {
        // Логика подфильтров
        const subFilterKey = `${filterId}_${layer.metadata.filter_id}`;
        const subFilterActive = filterStates[subFilterKey];
        const visibility = (isActive && subFilterActive) ? 'visible' : 'none';
        map.getLayer(layer.id) && map.setLayoutProperty(layer.id, 'visibility', visibility);
      } else {
        // Простое включение/выключение
        map.getLayer(layer.id) && map.setLayoutProperty(layer.id, 'visibility', isActive ? 'visible' : 'none');
      }
    }
  });
};
```

**Пример конфигурации стиля**:
```json
{
  "metadata": {
    "filters": {
      "weather": [
        {
          "id": "temperature",
          "name": "Температура"
        },
        {
          "id": "precipitation", 
          "name": "Осадки"
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

### Уровень 2: Расширенная фильтрация выражений

**Назначение**: Сложная фильтрация с использованием Mapbox-выражений для стилизации на основе данных.

### Как система различает уровни фильтрации

Система автоматически определяет, какой уровень фильтрации использовать, основываясь на наличии выражений `filter` в метаданных:

```javascript
const applyFilter = (filterId, isActive) => {
  if (currentMode !== 'filters' || !currentStyle?.metadata?.filters) return;
  
  const filterConfig = currentStyle.metadata.filters[filterId];
  if (!filterConfig) return;

  // Ключевая логика определения: проверяем, есть ли у фильтра свойство 'filter'
  const hasMapboxFilters = filterConfig.some(filter => filter.filter);
  
  // Направляем на соответствующий уровень фильтрации
  hasMapboxFilters ? applyLevel2Filter(filterId, isActive, filterConfig) : applyLevel1Filter(filterId, isActive, filterConfig);
};
```

**Логика определения**:
- **Уровень 1**: Когда `filterConfig.some(filter => filter.filter)` возвращает `false`
  - Нет выражений `filter` в метаданных
  - Только простое управление видимостью
- **Уровень 2**: Когда `filterConfig.some(filter => filter.filter)` возвращает `true`
  - Содержит выражения `filter` в метаданных
  - Расширенная фильтрация на основе выражений

**Пример - Определение Уровня 1**:
```json
{
  "metadata": {
    "filters": {
      "weather": [
        {
          "id": "temperature",
          "name": "Температура"
          // Нет свойства 'filter' = Уровень 1
        },
        {
          "id": "precipitation", 
          "name": "Осадки"
          // Нет свойства 'filter' = Уровень 1
        }
      ]
    }
  }
}
```

**Пример - Определение Уровня 2**:
```json
{
  "metadata": {
    "filters": {
      "airspace": [
        {
          "id": "controlled",
          "name": "Контролируемое воздушное пространство",
          "filter": ["==", ["get", "class"], "controlled"]  // Есть 'filter' = Уровень 2
        },
        {
          "id": "restricted",
          "name": "Запретные зоны", 
          "filter": ["==", ["get", "class"], "restricted"]  // Есть 'filter' = Уровень 2
        }
      ]
    }
  }
}
```

**Реализация**:
```javascript
const applyLevel2Filter = (filterId, isActive, filterConfig) => {
  const subFiltersWithExpr = filterConfig.filter(f => !!f.filter);
  const generalLayers = currentStyle.layers.filter(layer => layer.metadata?.filter_id === filterId);
  
  if (!isActive) {
    // Отключить все слои
    generalLayers.forEach(layer => {
      if (map.getLayer(layer.id)) {
        map.setLayoutProperty(layer.id, 'visibility', 'none');
        map.setFilter(layer.id, null);
      }
    });
    return;
  }

  // Применить фильтры выражений
  const activeWithExpr = subFiltersWithExpr.filter(f => filterStates[`${filterId}_${f.id}`] !== false);
  
  if (activeWithExpr.length === 1) {
    // Один фильтр - применить напрямую
    const expr = activeWithExpr[0].filter;
    generalLayers.forEach(layer => {
      if (map.getLayer(layer.id)) {
        map.setLayoutProperty(layer.id, 'visibility', 'visible');
        map.setFilter(layer.id, expr);
      }
    });
  } else if (activeWithExpr.length > 1) {
    // Несколько фильтров - объединить с логикой ИЛИ
    const exprs = activeWithExpr.map(f => f.filter);
    const combined = ['any', ...exprs];
    generalLayers.forEach(layer => {
      if (map.getLayer(layer.id)) {
        map.setLayoutProperty(layer.id, 'visibility', 'visible');
        map.setFilter(layer.id, combined);
      }
    });
  }
};
```

**Пример конфигурации стиля**:
```json
{
  "metadata": {
    "filters": {
      "airspace": [
        {
          "id": "controlled",
          "name": "Контролируемое воздушное пространство",
          "filter": ["==", ["get", "class"], "controlled"]
        },
        {
          "id": "restricted",
          "name": "Запретные зоны", 
          "filter": ["==", ["get", "class"], "restricted"]
        },
        {
          "id": "danger",
          "name": "Опасные зоны",
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

## Двухрежимный интерфейс

### Режим фильтров

**Назначение**: Управление слоями через фильтры, определенные в метаданных, с поддержкой подфильтров.

**Возможности**:
- Групповая фильтрация
- Переключатели подфильтров
- Сохранение состояния
- Поддержка сложных выражений

**Структура UI**:
```html
<div class="filter-group">
  <button class="filter-group-button">Погода</button>
  <div class="filter-sub-buttons">
    <button class="filter-sub-button">Температура</button>
    <button class="filter-sub-button">Осадки</button>
  </div>
</div>
```

### Режим слоев

**Назначение**: Прямое управление видимостью слоев без логики фильтрации.

**Возможности**:
- Индивидуальные переключатели слоев
- Массовые операции (переключить все)
- Простые состояния включения/выключения

**Реализация**:
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

## Мониторинг производительности

### Метрики в реальном времени

Система предоставляет комплексный мониторинг производительности:

```javascript
const updatePerformanceMetrics = () => {
  // Расчет FPS
  const fps = Math.round((frameCount * 1000) / (now - lastFpsTime));
  
  // Использование памяти
  const memoryMB = Math.round(performance.memory.usedJSHeapSize / 1024 / 1024);
  
  // Подсчет активных слоев
  let activeLayers = 0;
  currentStyle.layers.forEach(layer => {
    if (map.getLayer(layer.id)) {
      const visibility = map.getLayoutProperty(layer.id, 'visibility');
      if (visibility === 'visible') activeLayers++;
    }
  });
  
  // Уровень зума
  const zoom = map.getZoom();
};
```

### Отображение метрик

- **FPS**: Частота кадров в реальном времени с цветовым кодированием
- **Время кадра**: Среднее время рендеринга кадра
- **Использование памяти**: Использование JavaScript heap
- **Активные слои**: Количество видимых слоев
- **Уровень зума**: Текущий зум карты
- **Загруженные тайлы**: Количество загруженных источников тайлов

## Синхронизация карт

### Двухкартовая система

Система использует две синхронизированные карты:

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

**Назначение**:
- Базовая карта предоставляет контекст
- Карта стиля показывает отфильтрованные данные
- Синхронизированная навигация
- Переключаемая видимость базовой карты

## Управление состоянием

### Состояния фильтров

```javascript
let filterStates = {};
let layerStates = {};
let subFilterStatesBeforeGroupToggle = {};
```

**Структура состояния**:
- `filterStates[filterId]`: Булево состояние для основных фильтров
- `filterStates[filterId_subFilterId]`: Булево состояние для подфильтров
- `layerStates[layerId]`: Булево состояние для отдельных слоев
- `subFilterStatesBeforeGroupToggle`: Временное хранилище для операций переключения групп

### Сохранение состояния

Состояния поддерживаются во время:
- Переключения режимов
- Переключения фильтров
- Операций со слоями
- Взаимодействий с картой

## Обработка ошибок

### Graceful Degradation

```javascript
// Создание карты с обработкой ошибок
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

// Логирование ошибок
map.on('error', (e) => { 
  console.error('[MapLibre ERROR]', e?.error || e); 
});
```

### Загрузка ресурсов

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

## Примеры использования

### Базовая реализация

```html
<!-- HTML структура -->
<div id="map-container">
  <div id="map_base" class="map-layer"></div>
  <div id="map" class="map-layer" data-style-url="/styles/example-style"></div>
  
  <div class="layer-controls">
    <div class="mode-switcher">
      <button class="mode-button active" onclick="switchMode(this, 'filters')">Фильтры</button>
      <button class="mode-button" onclick="switchMode(this, 'layers')">Слои</button>
    </div>
    
    <div id="filters-panel" class="control-panel active">
      <button onclick="toggleAllFilters()">Переключить все фильтры</button>
      <div id="filter-buttons"></div>
    </div>
    
    <div id="layers-panel" class="control-panel">
      <button onclick="toggleAllLayers()">Переключить все слои</button>
      <div id="layer-buttons"></div>
    </div>
  </div>
</div>
```

### Конфигурация стиля

```json
{
  "version": 8,
  "name": "Пример стиля",
  "metadata": {
    "filters": {
      "transport": [
        {
          "id": "roads",
          "name": "Дороги",
          "filter": ["==", ["get", "type"], "road"]
        },
        {
          "id": "railways",
          "name": "Железные дороги", 
          "filter": ["==", ["get", "type"], "railway"]
        }
      ],
      "poi": [
        {
          "id": "restaurants",
          "name": "Рестораны"
        },
        {
          "id": "shops",
          "name": "Магазины"
        }
      ]
    },
    "locale": {
      "ru": {
        "transport": "Транспорт",
        "roads": "Дороги",
        "railways": "Железные дороги",
        "poi": "Точки интереса",
        "restaurants": "Рестораны",
        "shops": "Магазины"
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

## Лучшие практики

### Дизайн стилей

1. **Последовательные метаданные**: Используйте последовательное именование filter_id
2. **Логическая группировка**: Группируйте связанные слои под осмысленными именами фильтров
3. **Оптимизация выражений**: Используйте эффективные Mapbox-выражения
4. **Локализация**: Предоставляйте данные локализации для меток UI

### Производительность

1. **Оптимизация слоев**: Минимизируйте количество слоев
2. **Эффективность фильтров**: Используйте простые фильтры когда возможно
3. **Управление ресурсами**: Мониторьте использование памяти
4. **Обработка ошибок**: Реализуйте graceful fallbacks

### Пользовательский опыт

1. **Интуитивные элементы управления**: Четкие метки кнопок и группировка
2. **Обратная связь состояния**: Визуальная индикация активных состояний
3. **Мониторинг производительности**: Отображение метрик в реальном времени
4. **Адаптивный дизайн**: Адаптация к различным размерам экрана

## Устранение неполадок

### Распространенные проблемы

1. **Слои не видны**: Проверьте состояния фильтров и метаданные слоев
2. **Проблемы производительности**: Мониторьте FPS и использование памяти
3. **Фильтр не работает**: Проверьте синтаксис выражений и свойства данных
4. **Потеря состояния**: Проверьте управление состоянием при переключении режимов

### Инструменты отладки

- Консоль браузера для сообщений об ошибках
- Панель производительности для метрик
- Вкладка Network для загрузки ресурсов
- Режим отладки MapLibre для детального логирования
