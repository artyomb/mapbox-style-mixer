require 'spec_helper'

RSpec.describe 'Sprite Handling for Non-Standard Styles' do
  let(:config) { { 'styles' => { 'test_mix' => { 'id' => 'test', 'name' => 'Test Style', 'sources' => ['https://example.com/style.json'] } } } }
  let(:downloader) { StyleDownloader.new(config) }
  
  before { FakeFS.activate! && FileUtils.mkdir_p('raw_styles') }
  after { FakeFS.deactivate! }

  describe 'extract_sprite_url' do
    it 'handles standard sprite field' do
      style = { 'sprite' => 'https://example.com/sprite' }
      expect(downloader.send(:extract_sprite_url, style)).to eq('https://example.com/sprite')
    end

    it 'handles sprites array field' do
      style = { 'sprites' => ['https://example.com/sprite'] }
      expect(downloader.send(:extract_sprite_url, style)).to eq('https://example.com/sprite')
    end

    it 'handles empty sprites array' do
      style = { 'sprites' => [] }
      expect(downloader.send(:extract_sprite_url, style)).to be_nil
    end

    it 'handles missing sprite fields' do
      style = {}
      expect(downloader.send(:extract_sprite_url, style)).to be_nil
    end

    it 'handles empty sprite string' do
      style = { 'sprite' => '' }
      expect(downloader.send(:extract_sprite_url, style)).to be_nil
    end
  end

  describe 'valid_url?' do
    it 'validates proper URLs' do
      expect(downloader.send(:valid_url?, 'https://example.com/sprite')).to be true
      expect(downloader.send(:valid_url?, 'http://example.com/sprite')).to be true
    end

    it 'rejects invalid URLs' do
      expect(downloader.send(:valid_url?, 'link')).to be false
      expect(downloader.send(:valid_url?, 'null')).to be false
      expect(downloader.send(:valid_url?, '')).to be false
      expect(downloader.send(:valid_url?, nil)).to be false
      expect(downloader.send(:valid_url?, 'invalid-url')).to be false
    end
  end

  describe 'extract_sprites' do
    it 'extracts valid sprites' do
      style = { 'sprite' => 'https://example.com/sprite' }
      sprites = downloader.send(:extract_sprites, style, 'test_mix', 'test_style', 1)
      expect(sprites.length).to eq(2)
      expect(sprites.first[:url]).to eq('https://example.com/sprite')
      expect(sprites.last[:url]).to eq('https://example.com/sprite@2x')
    end

    it 'handles invalid sprites gracefully' do
      style = { 'sprite' => 'link' }
      sprites = downloader.send(:extract_sprites, style, 'test_mix', 'test_style', 1)
      expect(sprites).to be_empty
    end

    it 'handles sprites array' do
      style = { 'sprites' => ['https://example.com/sprite'] }
      sprites = downloader.send(:extract_sprites, style, 'test_mix', 'test_style', 1)
      expect(sprites.length).to eq(2)
      expect(sprites.first[:url]).to eq('https://example.com/sprite')
      expect(sprites.last[:url]).to eq('https://example.com/sprite@2x')
    end

    it 'handles invalid sprites array' do
      style = { 'sprites' => ['link'] }
      sprites = downloader.send(:extract_sprites, style, 'test_mix', 'test_style', 1)
      expect(sprites).to be_empty
    end
  end
end
