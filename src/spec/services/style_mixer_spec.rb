require 'spec_helper'

RSpec.describe StyleMixer do
  let(:config) { sample_config }
  let(:mixer) { StyleMixer.new(config) }
  
  before do
    FakeFS.activate!
    FileUtils.mkdir_p('src/raw_styles')
    FileUtils.mkdir_p('src/mixed_styles')
    
    style1 = sample_style('weather').merge({
      'sources' => { 'weather_source' => { 'type' => 'vector' } },
      'layers' => [
        {
          'id' => 'weather_layer',
          'type' => 'fill',
          'source' => 'weather_source',
          'layout' => { 'text-font' => ['Weather-Font'] }
        }
      ],
      'metadata' => {
        'filters' => {
          'weather' => [{ 'id' => 'temp_filter' }]
        },
        'locale' => {
          'ru' => { 'weather' => 'Погода' }
        }
      }
    })
    
    style2 = sample_style('location').merge({
      'sources' => { 'location_source' => { 'type' => 'vector' } },
      'layers' => [
        {
          'id' => 'location_layer',
          'type' => 'symbol',
          'source' => 'location_source',
          'layout' => { 'text-font' => ['Location-Font'] }
        }
      ],
      'metadata' => {
        'filters' => {
          'locations' => [{ 'id' => 'city_filter' }]
        },
        'locale' => {
          'ru' => { 'locations' => 'Локации' }
        }
      }
    })
    
    File.write('src/raw_styles/test_mix_weather_1.json', style1.to_json)
    File.write('src/raw_styles/test_mix_location_2.json', style2.to_json)
    
    allow_any_instance_of(SpriteMerger).to receive(:merge_sprites_for_mix).and_return({
      png: 'src/sprite/test_mix_sprite.png',
      json: 'src/sprite/test_mix_sprite.json'
    })
    
    allow(File).to receive(:write).and_call_original
  end

  after do
    FakeFS.deactivate!
  end

  describe '#mix_all_styles' do
    it 'mixes all styles from config' do
      expect { mixer.mix_all_styles }.not_to raise_error
      
      expect(Dir.glob('src/mixed_styles/*.json')).not_to be_empty
    end

    it 'handles errors for individual styles gracefully' do
      allow(mixer).to receive(:mix_styles).and_raise('Test error')
      expect { mixer.mix_all_styles }.not_to raise_error
    end
  end

  describe '#mix_styles' do
    let(:mix_config) { config['styles']['test_mix'] }
    
    it 'creates mixed style with correct structure' do
      result = mixer.mix_styles('test_mix', mix_config)
      
      expect(result['version']).to eq(8)
      expect(result['name']).to eq('Test Mix Style')
      expect(result['id']).to eq('test_mix')
      expect(result['sources']).to be_a(Hash)
      expect(result['layers']).to be_an(Array)
      expect(result['metadata']).to be_a(Hash)
    end

    it 'includes sources from all styles' do
      result = mixer.mix_styles('test_mix', mix_config)
      
      expect(result['sources']).to be_a(Hash)
      expect(result['sources'].keys.length).to be > 0
    end

    it 'includes layers from all styles' do
      result = mixer.mix_styles('test_mix', mix_config)
      
      expect(result['layers']).to be_an(Array)
      expect(result['layers'].length).to be > 0
    end

    it 'processes font references' do
      result = mixer.mix_styles('test_mix', mix_config)
      
      layers_with_fonts = result['layers'].select { |layer| layer.dig('layout', 'text-font') }
      expect(layers_with_fonts).not_to be_empty
    end

    it 'sets sprite and glyphs URLs correctly' do
      result = mixer.mix_styles('test_mix', mix_config)
      
      expect(result['sprite']).to eq('/sprite/test_mix_sprite')
      expect(result['glyphs']).to eq('/fonts/{fontstack}/{range}.pbf')
    end

    it 'creates mixed style file' do
      mixer.mix_styles('test_mix', mix_config)
      
      expect(File.exist?('src/mixed_styles/test_mix.json')).to be true
    end
  end

  describe 'error handling' do
    it 'handles missing source files gracefully' do
      File.delete('src/raw_styles/test_mix_weather_1.json')
      File.delete('src/raw_styles/test_mix_location_2.json')
      
      expect { mixer.mix_styles('test_mix', mix_config) }.not_to raise_error
    end

    it 'handles invalid JSON gracefully' do
      File.write('src/raw_styles/test_mix_invalid_1.json', 'invalid json')
      
      expect { mixer.mix_all_styles }.not_to raise_error
    end
  end
end