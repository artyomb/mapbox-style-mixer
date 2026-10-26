require 'spec_helper'

RSpec.describe GlyphPbf do
  let(:empty_range) { "\x0a\x10\x0a\x07Fixture\x12\x050-255".b }

  it 'accepts a correctly encoded empty Unicode range' do
    expect(described_class.validate!(empty_range)).to be(true)
  end

  ['<html>error</html>', '{"error":"unavailable"}', "\x0f".b, "\x0a\x05\x0a".b, ''.b].each do |bytes|
    it "rejects invalid glyph data #{bytes.inspect}" do
      expect { described_class.validate!(bytes) }.to raise_error(GlyphPbf::InvalidData)
    end
  end

  it 'rejects a glyph missing required metrics' do
    bytes = GlyphPbf::Message.encode(GlyphPbf::Message.new(stacks: [GlyphPbf::Fontstack.new(name: 'Fixture', range: '0-255',
                                                                                       glyphs: [GlyphPbf::Glyph.new(id: 65)])]))
    expect { described_class.validate!(bytes) }.to raise_error(GlyphPbf::InvalidData, /metrics/)
  end

  it 'rejects a bitmap inconsistent with its dimensions' do
    glyph = GlyphPbf::Glyph.new(id: 65, width: 1, height: 1, left: 0, top: 0, advance: 1, bitmap: 'x')
    bytes = GlyphPbf::Message.encode(GlyphPbf::Message.new(stacks: [GlyphPbf::Fontstack.new(name: 'Fixture', range: '0-255', glyphs: [glyph])]))
    expect { described_class.validate!(bytes) }.to raise_error(GlyphPbf::InvalidData, /dimensions/)
  end

  it 'rejects an invalid public fallback response without overwriting a cached glyph' do
    FakeFS do
      FileUtils.mkdir_p('/fonts')
      File.binwrite('/fonts/0-255.pbf', empty_range)
      stub_request(:get, 'https://demotiles.maplibre.org/font/Fixture/0-255.pbf').to_return(status: 200, body: '<html>error</html>')
      result = StyleDownloader.new({ 'styles' => {} }).send(:try_download_from_fallback, '/fonts', '0-255.pbf', 'Fixture', '0-255')
      expect(result).to be(false)
      expect(File.binread('/fonts/0-255.pbf')).to eq(empty_range)
    end
  end
end
