require 'spec_helper'

RSpec.describe SpriteMerger do
  let(:config) { sample_config }
  let(:merger) { SpriteMerger.new(config) }

  before do
    FakeFS.activate!
    FileUtils.mkdir_p('src/sprites')
    FileUtils.mkdir_p('src/sprite')
    
    create_sprite_dir('test_mix_weather_1', {
      'icon1' => { 'width' => 24, 'height' => 24, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 },
      'icon2' => { 'width' => 32, 'height' => 32, 'x' => 24, 'y' => 0, 'pixelRatio' => 1 }
    })
    
    create_sprite_dir('test_mix_location_2', {
      'icon3' => { 'width' => 16, 'height' => 16, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 }
    })
  end

  after do
    FakeFS.deactivate!
  end

  describe '#merge_all_sprites' do
    it 'runs without errors' do
      expect { merger.merge_all_sprites }.not_to raise_error
    end

    it 'handles errors for individual mixes gracefully' do
      allow(merger).to receive(:merge_sprites_for_mix).and_raise(StandardError.new('Test error'))
      expect { merger.merge_all_sprites }.not_to raise_error
    end
  end

  describe '#merge_sprites_for_mix' do
    it 'returns nil when no sprites found' do
      FileUtils.rm_rf('src/sprites/test_mix_weather_1')
      FileUtils.rm_rf('src/sprites/test_mix_location_2')
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).to be_nil
    end

    it 'finds sprite directories correctly' do
      dirs = Dir.glob('src/sprites/test_mix_*')
      expect(dirs.length).to eq(2)
      expect(dirs.map { |d| d.sub('/src/', 'src/') }).to include('src/sprites/test_mix_weather_1')
      expect(dirs.map { |d| d.sub('/src/', 'src/') }).to include('src/sprites/test_mix_location_2')
    end

    it 'handles missing sprite files gracefully' do
      FileUtils.mkdir_p('src/sprites/test_mix_empty_3')
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).to be_nil  # Should return nil because ImageMagick will fail
    end
  end

  describe 'sprite file structure' do
    it 'creates sprite files with correct format' do
      expect(File.exist?('src/sprites/test_mix_weather_1/sprite.json')).to be true
      expect(File.exist?('src/sprites/test_mix_weather_1/sprite.png')).to be true
      expect(File.exist?('src/sprites/test_mix_location_2/sprite.json')).to be true
      expect(File.exist?('src/sprites/test_mix_location_2/sprite.png')).to be true
    end

    it 'has valid JSON content' do
      json_content = JSON.parse(File.read('src/sprites/test_mix_weather_1/sprite.json'))
      expect(json_content).to be_a(Hash)
      expect(json_content).to have_key('icon1')
    end
  end

  describe 'configuration handling' do
    it 'uses provided config' do
      expect(merger.instance_variable_get(:@config)).to eq(config)
    end

    it 'sets correct directory paths' do
      sprites_dir = merger.instance_variable_get(:@sprites_dir)
      output_dir = merger.instance_variable_get(:@output_dir)
      
      expect(sprites_dir).to end_with('sprites')
      expect(output_dir).to end_with('sprite')
    end
  end

  describe 'error handling' do
    it 'handles JSON parse errors gracefully' do
      FileUtils.mkdir_p('src/sprites/test_mix_invalid_4')
      File.write('src/sprites/test_mix_invalid_4/sprite.json', 'invalid json')
      File.write('src/sprites/test_mix_invalid_4/sprite.png', 'fake_png')
      
      expect { merger.merge_sprites_for_mix('test_mix') }.not_to raise_error
    end
  end
end