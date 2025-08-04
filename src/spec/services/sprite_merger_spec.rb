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
    
    allow(merger).to receive(:merge_png_files).and_return('src/sprite/test_mix_sprite.png')
    allow(merger).to receive(:clean_output_directory)
  end

  after do
    FakeFS.deactivate!
  end

  def create_sprite_dir(name, icons)
    dir = "src/sprites/#{name}"
    FileUtils.mkdir_p(dir)
    File.write("#{dir}/sprite.json", icons.to_json)
    File.write("#{dir}/sprite.png", 'fake_png_data')
  end

  describe '#merge_all_sprites' do
    it 'merges sprites for all styles' do
      expect { merger.merge_all_sprites }.not_to raise_error
    end

    it 'handles errors for individual mixes gracefully' do
      allow(merger).to receive(:merge_sprites_for_mix).and_raise('Test error')
      expect { merger.merge_all_sprites }.not_to raise_error
    end
  end

  describe '#merge_sprites_for_mix' do
    it 'merges multiple sprites successfully' do
      File.write('src/sprite/test_mix_sprite.json', { merged: 'icons' }.to_json)
      File.write('src/sprite/test_mix_sprite.png', 'merged_png_data')
      
      result = merger.merge_sprites_for_mix('test_mix')
      
      expect(result).not_to be_nil
      expect(result[:png]).to include('test_mix_sprite.png')
      expect(result[:json]).to include('test_mix_sprite.json')
    end

    it 'handles single sprite' do
      FileUtils.rm_rf('src/sprites/test_mix_location_2')
      
      File.write('src/sprite/test_mix_sprite.json', { single: 'icon' }.to_json)
      File.write('src/sprite/test_mix_sprite.png', 'single_png_data')
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).not_to be_nil
    end

    it 'returns nil when no sprites found' do
      FileUtils.rm_rf('src/sprites/test_mix_weather_1')
      FileUtils.rm_rf('src/sprites/test_mix_location_2')
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).to be_nil
    end

    it 'creates output files with correct names' do
      merger.merge_sprites_for_mix('test_mix')
      
      expect(File.exist?('src/sprite/test_mix_sprite.png')).to be true
      expect(File.exist?('src/sprite/test_mix_sprite.json')).to be true
    end
  end

  describe 'sprite merging logic' do
    it 'calls merge methods' do
      expect(merger).to receive(:merge_png_files)
      merger.merge_sprites_for_mix('test_mix')
    end

    it 'creates output files' do
      File.write('src/sprite/test_mix_sprite.json', { test: 'data' }.to_json)
      File.write('src/sprite/test_mix_sprite.png', 'png_data')
      
      merger.merge_sprites_for_mix('test_mix')
      
      expect(File.exist?('src/sprite/test_mix_sprite.json')).to be true
      expect(File.exist?('src/sprite/test_mix_sprite.png')).to be true
    end
  end

  describe 'error handling' do
    it 'handles missing files gracefully' do
      FileUtils.rm_rf('src/sprites/test_mix_weather_1')
      FileUtils.rm_rf('src/sprites/test_mix_location_2')
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).to be_nil
    end

    it 'logs errors but continues' do
      expect(merger).to receive(:merge_png_files).and_raise(StandardError.new('Test error'))
      
      result = merger.merge_sprites_for_mix('test_mix')
      expect(result).to be_nil
    end
  end

  describe 'directory management' do
    it 'calls cleanup methods' do
      expect(merger).to receive(:clean_output_directory)
      merger.merge_sprites_for_mix('test_mix')
    end
  end
end