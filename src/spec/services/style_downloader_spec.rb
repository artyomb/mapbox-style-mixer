require 'spec_helper'

RSpec.describe StyleDownloader do
  let(:config) { sample_config }
  let(:downloader) { StyleDownloader.new(config) }
  let(:style1) { sample_style('style1') }
  let(:style2) { sample_style('style2') }

  before do
    FakeFS.activate!
    
    stub_style_request('https://example.com/style1.json', style1)
    stub_style_request('https://example.com/style2.json', style2)
    stub_sprite_requests('https://example.com/sprite')
    
    allow(downloader).to receive(:download_fonts_for_style).and_return(true)
    allow(downloader).to receive(:download_sprites_for_style).and_return(true)
  end

  after do
    FakeFS.deactivate!
  end

  describe '#download_all' do
    it 'downloads all styles from config' do
      expect { downloader.download_all }.not_to raise_error
      
      expect(Dir.exist?('src/raw_styles')).to be true
      expect(Dir.exist?('src/fonts')).to be true
      expect(Dir.exist?('src/sprites')).to be true
    end

    it 'saves style files with correct naming' do
      downloader.download_all
      
      files = Dir.glob('src/raw_styles/*.json')
      expect(files).not_to be_empty
      expect(files.any? { |f| f.include?('test_mix_style1_1.json') }).to be true
    end

    it 'downloads sprites when available' do
      downloader.download_all
      
      sprite_dirs = Dir.glob('src/sprites/test_mix_*')
      expect(sprite_dirs).not_to be_empty
    end
  end

  describe '#download_style' do
    it 'downloads specific style by mix_id' do
      expect { downloader.download_style('test_mix') }.not_to raise_error
    end

    it 'raises error for non-existing style' do
      expect { downloader.download_style('non_existing') }.to raise_error(/not found/)
    end
  end

  describe 'error handling' do
    it 'handles network errors gracefully' do
      stub_request(:get, 'https://example.com/style1.json')
        .to_raise(Faraday::Error)
      
      expect { downloader.download_all }.to raise_error(Faraday::Error)
    end

    it 'handles HTTP errors' do
      stub_request(:get, 'https://example.com/style1.json')
        .to_return(status: 404)
      
      expect { downloader.download_all }.to raise_error(/Failed to fetch/)
    end

    it 'handles invalid JSON' do
      stub_request(:get, 'https://example.com/style1.json')
        .to_return(status: 200, body: 'invalid json')
      
      expect { downloader.download_all }.to raise_error(JSON::ParserError)
    end
  end

  describe 'font downloading' do
    it 'calls font download methods' do
      expect(downloader).to receive(:download_fonts_for_style).at_least(:once)
      downloader.download_all
    end

    it 'creates font directory' do
      downloader.download_all
      expect(Dir.exist?('src/fonts')).to be true
    end
  end
end