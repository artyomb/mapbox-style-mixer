# Mapbox Style Mixer

Специализированный сервис для объединения и смешивания стилей Mapbox с поддержкой спрайтов, шрифтов и фильтров. Сервис загружает несколько исходных стилей, объединяет их в единые стили и предоставляет их через REST API.

[![Ruby](https://img.shields.io/badge/ruby-3.4+-red.svg)](https://ruby-lang.org)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](docker/)
[![Tests](https://img.shields.io/badge/tests-passing-green.svg)](src/spec/)
[![English](https://img.shields.io/badge/english-documentation-blue.svg)](../../../readme.md)

## Ключевые возможности

- **Смешивание стилей**: Объединение нескольких стилей Mapbox в единые стили с автоматическим управлением префиксами
- **Объединение спрайтов**: Автоматическое объединение изображений спрайтов и метаданных с помощью ImageMagick
- **Управление шрифтами**: Загрузка и кэширование файлов шрифтов с поддержкой диапазонов (0-255, 256-511, и т.д.)
- **Расширенная фильтрация**: Двухуровневая система фильтрации с выражениями Mapbox и управлением слоями в реальном времени
- **Интерактивный предварительный просмотр**: Веб-интерфейс карты с двухрежимным управлением (фильтры/слои) и мониторингом производительности
- **REST API**: Полный API для предоставления стилей с поддержкой аутентификации
- **Готовность к Docker**: Контейнеризованное развертывание с монтированием томов для конфигурации

## Архитектура

Сервис состоит из нескольких ключевых компонентов:

- **[Style Mixer](style_mixer.md)** - Объединяет несколько стилей Mapbox с управлением префиксами
- **[Style Downloader](style_downloader.md)** - Загружает исходные стили и ресурсы с поддержкой аутентификации
- **[Sprite Merger](sprite_merger.md)** - Объединяет спрайты с помощью ImageMagick
- **[Система предварительного просмотра карт](map_preview_system_ru.md)** - Расширенная фильтрация и управление слоями

## Быстрый старт

### Использование Docker

```bash
# Создание файла конфигурации
cat > styles_config.yaml << EOF
styles:
  my_style:
    id: 'my_combined_style'
    name: "Мой объединенный стиль"
    sources:
      - https://example.com/style1.json
      - https://example.com/style2.json
EOF

# Запуск с Docker
docker run --rm \
  -v $(pwd)/styles_config.yaml:/configs/styles_config.yaml \
  -p 7000:7000 \
  mapbox-style-mixer

# Доступ к сервису
open http://localhost:7000
```

### Локальная разработка

```bash
# Клонирование репозитория
git clone https://github.com/user/mapbox-style-mixer.git
cd mapbox-style-mixer

# Установка зависимостей
bundle install

# Запуск тестов
bundle exec rspec

# Запуск сервера разработки
bundle exec rackup
```

## Конфигурация

Сервис использует YAML файл конфигурации для определения комбинаций стилей:

```yaml
# styles_config.yaml
styles:
  weather_location:
    id: 'weather_location_1'
    name: "Стиль погоды и местоположения"
    sources:
      - https://example.com/styles/weather/weather
      - https://example.com/styles/location/location

  weather_location_tz:
    id: 'weather_location_tz_2'
    name: "Стиль погоды, местоположения и часовых поясов"
    sources:
      - https://example.com/styles/weather/weather
      - https://example.com/styles/location/location
      - https://example.com/styles/weather/timezones
```

## Справочник API

### Основные эндпоинты

| Эндпоинт | Метод | Описание | Ответ |
|----------|--------|-------------|----------|
| `/` | GET | Главный интерфейс со списком стилей | HTML |
| `/status` | GET | Статус инициализации сервиса | JSON |
| `/styles` | GET | Список всех доступных стилей | JSON |
| `/styles/:id` | GET | Получение JSON смешанного стиля | JSON |
| `/refresh` | GET | Перезагрузка и повторное смешивание всех стилей | Redirect |
| `/map` | GET | Интерактивный интерфейс предварительного просмотра карты | HTML |

### Эндпоинты ресурсов

| Эндпоинт | Метод | Описание | Ответ |
|----------|--------|-------------|----------|
| `/sprite/:id.png` | GET | Получение изображения спрайта | PNG |
| `/sprite/:id.json` | GET | Получение метаданных спрайта | JSON |
| `/fonts/*/:range.pbf` | GET | Получение файла шрифта | Binary |

### Примеры ответов

**GET /styles**
```json
{
  "available_styles": [
    {
      "id": "weather_location_1",
      "name": "Стиль погоды и местоположения",
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
  "message": "Готов"
}
```

## Структура файлов

```
src/
├── config.ru              # Основное приложение Sinatra
├── style_downloader.rb    # Сервис загрузки стилей
├── style_mixer.rb         # Логика смешивания стилей
├── sprite_merger.rb       # Сервис объединения спрайтов
├── configs/
│   └── styles_config.yaml # Файл конфигурации
├── views/                 # Шаблоны веб-интерфейса
│   ├── index.slim         # Главная страница
│   ├── map.slim           # Интерфейс предварительного просмотра карты
│   ├── map_layout.slim    # Шаблон макета карты
│   └── layout.slim        # Шаблон макета
├── public/                # Статические ресурсы
│   └── js/                # JavaScript файлы
│       └── filters.js     # Реализация системы фильтров
├── spec/                  # Набор тестов
├── mixed_styles/          # Сгенерированные смешанные стили
├── sprite/                # Объединенные файлы спрайтов
├── sprites/               # Исходные файлы спрайтов
├── raw_styles/            # Загруженные исходные стили
├── fonts/                 # Файлы шрифтов
└── docs/                  # Документация
    ├── en/                # Английская документация
    └── ru/                # Русская документация
```

## Разработка

### Предварительные требования

- Ruby 3.4+
- Bundler
- Docker (опционально)

### Настройка

```bash
# Установка зависимостей
bundle install

# Запуск тестов
bundle exec rspec

# Запуск сервера разработки
bundle exec rackup -p 7000

# Запуск с Docker
docker-compose up
```

### Тестирование

```bash
# Запуск всех тестов
bundle exec rspec

# Запуск конкретных категорий тестов
bundle exec rspec spec/api/
bundle exec rspec spec/services/
bundle exec rspec spec/integration/

# Запуск с покрытием
COVERAGE=true bundle exec rspec
```

## Развертывание

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

### Переменные окружения

- `CONFIG_PATH`: Путь к файлу конфигурации (по умолчанию: `configs/styles_config.yaml`)
- `RACK_ENV`: Режим окружения (development/production)

## Устранение неполадок

### Распространенные проблемы

**Стили не загружаются**
- Проверьте доступность исходных URL
- Проверьте синтаксис YAML конфигурации
- Проверьте логи сервиса на ошибки загрузки

**Спрайты не отображаются**
- Убедитесь, что ImageMagick установлен для объединения спрайтов
- Проверьте права доступа к файлам спрайтов
- Проверьте формат метаданных JSON спрайтов

**Шрифты не загружаются**
- Проверьте доступность файлов шрифтов
- Проверьте формат диапазона шрифтов (0-255, 256-511, и т.д.)
- Убедитесь в правах доступа к директории шрифтов

## Лицензия

Этот проект лицензирован под MIT License - см. файл [LICENSE](LICENSE) для подробностей.
