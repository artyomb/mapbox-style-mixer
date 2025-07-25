## styles_config.yaml

```yaml
styles:
  mix_style1:
    id: 'mix_style1'
    name: "Mix Style 1"
    sources:
      - https://...json
      - https://...json
      - https://...json
```

## Usage

```bash
 docker run --rm \
    -v $(pwd)/styles_config.yaml:/configs/styles_config.yaml \
    -p 7000:7000 \
    dtorry/mapbox-style-mixer
```