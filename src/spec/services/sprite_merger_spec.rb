require 'spec_helper'

RSpec.describe SpriteMerger do
  let(:config) { sample_config }
  let(:merger) { SpriteMerger.new(config) }

  before do
    FakeFS.activate!
    FileUtils.mkdir_p('src/sprites')
    FileUtils.mkdir_p('src/sprite')
    
    create_test_sprites
  end

  def create_test_sprites
    create_sprite_dir('test_mix_weather_1', {
      'icon1' => { 'width' => 24, 'height' => 24, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 },
      'icon2' => { 'width' => 32, 'height' => 32, 'x' => 24, 'y' => 0, 'pixelRatio' => 1 }
    })
    
    create_sprite_dir('test_mix_location_2', {
      'icon3' => { 'width' => 16, 'height' => 16, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 }
    })
    
    create_sprite_dir('test_mix_weather_1_@2x', {
      'icon1' => { 'width' => 48, 'height' => 48, 'x' => 0, 'y' => 0, 'pixelRatio' => 2 },
      'icon2' => { 'width' => 64, 'height' => 64, 'x' => 48, 'y' => 0, 'pixelRatio' => 2 }
    })
    
    create_sprite_dir('test_mix_location_2_@2x', {
      'icon3' => { 'width' => 32, 'height' => 32, 'x' => 0, 'y' => 0, 'pixelRatio' => 2 }
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
    it 'returns false when no sprites found' do
      FileUtils.rm_rf('src/sprites/test_mix_weather_1')
      FileUtils.rm_rf('src/sprites/test_mix_location_2')
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).to be false
    end

    it 'finds sprite directories correctly' do
      regular_dirs = Dir.glob('src/sprites/test_mix_*').select { |d| Dir.exist?(d) && !d.end_with?('_@2x') }
      expect(regular_dirs.length).to eq(2)
      expect(regular_dirs.map { |d| d.sub('/src/', 'src/') }).to include('src/sprites/test_mix_weather_1')
      expect(regular_dirs.map { |d| d.sub('/src/', 'src/') }).to include('src/sprites/test_mix_location_2')
    end

    it 'handles missing sprite files gracefully' do
      FileUtils.mkdir_p('src/sprites/test_mix_empty_3')
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).to be false 
    end
  end

  describe 'sprite deduplication' do
    before do
      create_duplicate_sprite_dir('test_mix_duplicate_1', {
        'icon1' => { 'width' => 24, 'height' => 24, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 }
      })
      create_duplicate_sprite_dir('test_mix_duplicate_2', {
        'icon1' => { 'width' => 24, 'height' => 24, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 }
      })
    end

    it 'removes duplicate sprites' do
      sprites = [
        merger.send(:load_sprite_data, 'src/sprites/test_mix_duplicate_1'),
        merger.send(:load_sprite_data, 'src/sprites/test_mix_duplicate_2')
      ].compact
      
      unique_sprites = merger.send(:deduplicate_sprites, sprites)
      expect(sprites.length).to eq(2)
      expect(unique_sprites.length).to eq(1)
    end

    it 'keeps unique sprites' do
      sprites = merger.send(:collect_sprite_files, 'test_mix')
      unique_sprites = merger.send(:deduplicate_sprites, sprites)
      expect(unique_sprites.length).to eq(sprites.length)
    end

    it 'handles edge cases' do
      expect(merger.send(:deduplicate_sprites, [])).to eq([])
      expect(merger.send(:deduplicate_sprites, [sprite1 = merger.send(:load_sprite_data, 'src/sprites/test_mix_weather_1')])).to eq([sprite1])
    end
  end

  describe 'sprite hash computation' do
    it 'computes consistent hash for identical sprites' do
      sprite1 = sprite2 = merger.send(:load_sprite_data, 'src/sprites/test_mix_weather_1')
      expect(merger.send(:compute_sprite_hash, sprite1)).to eq(merger.send(:compute_sprite_hash, sprite2))
    end

    it 'computes different hash for different sprites' do
      sprite1 = merger.send(:load_sprite_data, 'src/sprites/test_mix_weather_1')
      sprite2 = merger.send(:load_sprite_data, 'src/sprites/test_mix_location_2')
      expect(merger.send(:compute_sprite_hash, sprite1)).not_to eq(merger.send(:compute_sprite_hash, sprite2))
    end
  end

  describe 'sprite identity check' do
    it 'identifies identical sprites' do
      sprite1 = sprite2 = merger.send(:load_sprite_data, 'src/sprites/test_mix_weather_1')
      expect(merger.send(:sprites_identical?, sprite1, sprite2)).to be true
    end

    it 'identifies different sprites' do
      sprite1 = merger.send(:load_sprite_data, 'src/sprites/test_mix_weather_1')
      sprite2 = merger.send(:load_sprite_data, 'src/sprites/test_mix_location_2')
      expect(merger.send(:sprites_identical?, sprite1, sprite2)).to be false
    end

    it 'handles nil sprites' do
      sprite1 = merger.send(:load_sprite_data, 'src/sprites/test_mix_weather_1')
      expect(merger.send(:sprites_identical?, nil, sprite1)).to be false
      expect(merger.send(:sprites_identical?, sprite1, nil)).to be false
      expect(merger.send(:sprites_identical?, nil, nil)).to be false
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

  private

  def create_duplicate_sprite_dir(name, icons)
    dir = "src/sprites/#{name}"
    FileUtils.mkdir_p(dir)
    
    File.write("#{dir}/sprite.png", 'duplicate_png_content')
    File.write("#{dir}/sprite.json", JSON.pretty_generate(icons))
  end
end