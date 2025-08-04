require 'spec_helper'

RSpec.describe 'Full Workflow Integration' do
  before { [StyleDownloader, StyleMixer, SpriteMerger].each { |klass| allow_any_instance_of(klass).to receive_messages(download_all: true, mix_all_styles: true, merge_all_sprites: true) } }
  
  let(:test_config) { { 'styles' => { 'integration_test' => { 'id' => 'integration_test', 'name' => 'Integration Test Style', 'sources' => %w[https://example.com/weather.json https://example.com/location.json] } } } }

  before do
    FakeFS.activate!
    
    %w[weather location].each { |name| stub_request(:get, "https://example.com/#{name}.json").to_return(status: 200, body: { id: name, name: "#{name.capitalize} Style" }.to_json) }
    
    %w[weather location].each do |type|
      %w[json png].each { |ext| stub_request(:get, "https://#{type}.example.com/sprite.#{ext}").to_return(status: 200, body: ext == 'json' ? { icon: { width: 24, height: 24 } }.to_json : 'sprite_data') }
    end
    
    [%r{https://.*\.example\.com/fonts/.*/.*\.pbf}, %r{https://demotiles\.maplibre\.org/font/.*/.*\.pbf}].each { |pattern| stub_request(:get, pattern).to_return(status: 200, body: 'font_data') }
  end

  after { FakeFS.deactivate! }

  describe 'complete workflow' do
    it('executes all workflow steps without errors') { [StyleDownloader, StyleMixer, SpriteMerger].each { |klass| expect { klass.new(test_config).send(klass == StyleDownloader ? :download_all : klass == StyleMixer ? :mix_all_styles : :merge_all_sprites) }.not_to raise_error } }
  end
end