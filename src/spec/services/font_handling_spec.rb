require 'spec_helper'

RSpec.describe 'Font Handling for Dynamic Fonts' do
  let(:config) { { 'styles' => { 'test_mix' => { 'id' => 'test', 'name' => 'Test Style', 'sources' => ['https://example.com/style.json'] } } } }
  let(:downloader) { StyleDownloader.new(config) }
  let(:mixer) { StyleMixer.new(config) }
  
  before { FakeFS.activate! && FileUtils.mkdir_p('raw_styles') }
  after { FakeFS.deactivate! }

  describe 'extract_fonts' do
    it 'handles array fonts' do
      fonts = downloader.send(:extract_fonts, ['Roboto Regular', 'Arial Unicode MS Regular'])
      expect(fonts).to eq(['Roboto Regular', 'Arial Unicode MS Regular'])
    end

    it 'handles dynamic fonts with stops' do
      font_config = {
        'stops' => [
          [6, ['Roboto Regular']],
          [7, ['Roboto Bold']]
        ]
      }
      fonts = downloader.send(:extract_fonts, font_config)
      expect(fonts).to eq(['Roboto Regular', 'Roboto Bold'])
    end

    it 'handles missing text-font' do
      fonts = downloader.send(:extract_fonts, nil)
      expect(fonts).to eq([])
    end

    it 'handles invalid font config' do
      fonts = downloader.send(:extract_fonts, 'invalid')
      expect(fonts).to eq([])
    end
  end

  describe 'extract_from_stops' do
    it 'extracts fonts from valid stops' do
      stops = [[6, ['Roboto Regular']], [7, ['Roboto Bold']]]
      fonts = downloader.send(:extract_from_stops, stops)
      expect(fonts).to eq(['Roboto Regular', 'Roboto Bold'])
    end

    it 'handles single font in stop' do
      stops = [[6, 'Roboto Regular'], [7, 'Roboto Bold']]
      fonts = downloader.send(:extract_from_stops, stops)
      expect(fonts).to eq(['Roboto Regular', 'Roboto Bold'])
    end

    it 'handles invalid stops' do
      fonts = downloader.send(:extract_from_stops, 'invalid')
      expect(fonts).to eq([])
    end
  end

  describe 'process_text_font' do
    it 'processes array fonts with prefix' do
      font_config = ['Roboto Regular', 'Arial Unicode MS Regular']
      result = mixer.send(:process_text_font, font_config, 'test_prefix')
      expect(result).to eq(['test_prefix/Roboto Regular', 'test_prefix/Arial Unicode MS Regular'])
    end

    it 'processes dynamic fonts with prefix' do
      font_config = {
        'stops' => [
          [6, ['Roboto Regular']],
          [7, ['Roboto Bold']]
        ]
      }
      result = mixer.send(:process_text_font, font_config, 'test_prefix')
      expected = {
        'stops' => [
          [6, ['test_prefix/Roboto Regular']],
          [7, ['test_prefix/Roboto Bold']]
        ]
      }
      expect(result).to eq(expected)
    end

    it 'handles single font in dynamic config' do
      font_config = {
        'stops' => [
          [6, 'Roboto Regular'],
          [7, 'Roboto Bold']
        ]
      }
      result = mixer.send(:process_text_font, font_config, 'test_prefix')
      expected = {
        'stops' => [
          [6, ['test_prefix/Roboto Regular']],
          [7, ['test_prefix/Roboto Bold']]
        ]
      }
      expect(result).to eq(expected)
    end
  end
end
