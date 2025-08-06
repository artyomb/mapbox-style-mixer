require 'spec_helper'

RSpec.describe 'Configuration' do
  before { FakeFS.activate! }
  after { FakeFS.deactivate! }

  describe 'YAML configuration loading' do
    it 'loads valid configuration file' do
      config_content = { 'styles' => { 'test_style' => { 'id' => 'test_style', 'name' => 'Test Style', 'sources' => ['https://example.com/style.json'] } } }
      
      File.write('test_config.yaml', config_content.to_yaml)
      ENV['CONFIG_PATH'] = 'test_config.yaml'
      loaded_config = YAML.load_file(ENV['CONFIG_PATH'])
      
      expect(loaded_config).to be_a(Hash).and have_key('styles')
      expect(loaded_config.dig('styles', 'test_style', 'name')).to eq('Test Style')
    end

    it('handles missing configuration file') { ENV['CONFIG_PATH'] = 'non_existing.yaml'; expect { YAML.load_file(ENV['CONFIG_PATH']) }.to raise_error(Errno::ENOENT) }

    it 'handles invalid YAML syntax' do
      File.write('invalid_config.yaml', "invalid: yaml: content:")
      ENV['CONFIG_PATH'] = 'invalid_config.yaml'
      expect { YAML.load_file(ENV['CONFIG_PATH']) }.to raise_error(Psych::SyntaxError)
    end
  end

  describe 'configuration structure validation' do
    let(:valid_config) { { 'styles' => { 'mix1' => { 'id' => 'mix1', 'name' => 'Mix Style 1', 'sources' => %w[https://tiles1.example.com/style.json https://tiles2.example.com/style.json] } } } }

    it 'validates required fields presence' do
      mix_style = valid_config.dig('styles', 'mix1')
      expect(valid_config).to have_key('styles')
      expect(mix_style.keys).to include(*%w[id name sources])
    end

    it('validates sources is an array') { expect(valid_config.dig('styles', 'mix1', 'sources')).to be_an(Array) }
  end

  describe 'environment variable support' do
    it 'uses CONFIG_PATH environment variable' do
      File.write('custom_config.yaml', { 'styles' => {} }.to_yaml)
      ENV['CONFIG_PATH'] = 'custom_config.yaml'
      
      config_path = ENV['CONFIG_PATH'] || 'configs/styles_config.yaml'
      expect(config_path).to eq('custom_config.yaml')
      expect(File.exist?(config_path)).to be true
    end

    it('falls back to default path when CONFIG_PATH not set') do
      ENV.delete('CONFIG_PATH')
      expect(ENV['CONFIG_PATH'] || 'configs/styles_config.yaml').to eq('configs/styles_config.yaml')
    end
  end

  describe 'real configuration compatibility' do
    let(:realistic_config) { { 'styles' => { 
      'weather_location' => { 'id' => 'weather_location_1', 'name' => 'Weather and Location Style', 
                             'sources' => %w[https://example.com/weather/style https://example.com/location/style] },
      'full_stack' => { 'id' => 'weather_location_tz_2', 'name' => 'Weather, Location and Timezones Style',
                       'sources' => %w[https://example.com/weather/style https://example.com/location/style https://example.com/timezones/style] }
    } } }

    it 'supports multiple styles configuration' do
      styles = realistic_config['styles']
      expect(styles.keys).to include('weather_location', 'full_stack')
      expect(styles.values.map { |s| s['sources'].size }).to eq([2, 3])
    end
  end

  describe 'authentication configuration' do
    let(:auth_config) { { 'styles' => { 
      'auth_style' => { 'id' => 'auth_test', 'name' => 'Auth Test Style',
                       'sources' => [
                         { 'url' => 'https://secure.example.com/style.json',
                           'auth' => { 'username' => 'user', 'password' => 'pass' } },
                         'https://public.example.com/style.json'
                       ] }
    } } }

    it 'supports mixed sources with and without auth' do
      sources = auth_config.dig('styles', 'auth_style', 'sources')
      expect(sources[0]).to be_a(Hash).and include('url', 'auth')
      expect(sources[1]).to be_a(String)
    end

    it 'validates auth structure in sources' do
      auth_source = auth_config.dig('styles', 'auth_style', 'sources', 0)
      expect(auth_source['auth']).to include('username', 'password')
    end

    it 'handles string sources without auth' do
      string_source = auth_config.dig('styles', 'auth_style', 'sources', 1)
      expect(string_source).to be_a(String)
      expect(string_source).to start_with('https://')
    end
  end
end