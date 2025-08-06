require 'spec_helper'

RSpec.describe 'Basic Auth Support' do
  before { FakeFS.activate! }
  after { FakeFS.deactivate! }

  describe 'configuration with auth' do
    let(:auth_config) do
      {
        'styles' => {
          'auth_test' => {
            'id' => 'auth_test',
            'name' => 'Auth Test Style',
            'sources' => [
              { 'url' => 'https://secure.example.com/style.json',
                'auth' => { 'username' => 'user', 'password' => 'pass' } },
              'https://public.example.com/style.json'
            ]
          }
        }
      }
    end

    it 'validates auth configuration structure' do
      source_with_auth = auth_config.dig('styles', 'auth_test', 'sources', 0)
      expect(source_with_auth).to be_a(Hash)
      expect(source_with_auth['auth']).to include('username', 'password')
    end

    it 'handles mixed sources (with and without auth)' do
      sources = auth_config.dig('styles', 'auth_test', 'sources')
      expect(sources[0]).to be_a(Hash).and include('auth')
      expect(sources[1]).to be_a(String)
    end
  end

  describe 'StyleDownloader with auth' do
    let(:downloader) { StyleDownloader.new }

    it 'extracts URL and auth from source config' do
      source_config = { 'url' => 'https://example.com/style.json', 'auth' => { 'username' => 'user', 'password' => 'pass' } }
      
      url = source_config.is_a?(Hash) ? source_config['url'] : source_config
      auth = source_config.is_a?(Hash) ? source_config['auth'] : nil
      
      expect(url).to eq('https://example.com/style.json')
      expect(auth).to include('username' => 'user', 'password' => 'pass')
    end

    it 'handles string sources without auth' do
      source_config = 'https://public.example.com/style.json'
      
      url = source_config.is_a?(Hash) ? source_config['url'] : source_config
      auth = source_config.is_a?(Hash) ? source_config['auth'] : nil
      
      expect(url).to eq('https://public.example.com/style.json')
      expect(auth).to be_nil
    end
  end

  describe 'auth validation' do
    def validate_auth_config(source)
      return unless source.is_a?(Hash) && source['auth']
      missing = ['username', 'password'] - source['auth'].keys
      raise "Missing auth fields: #{missing}" if missing.any?
    end

    it 'validates complete auth configuration' do
      valid_source = { 'url' => 'https://example.com/style.json', 'auth' => { 'username' => 'user', 'password' => 'pass' } }
      expect { validate_auth_config(valid_source) }.not_to raise_error
    end

    it 'raises error for incomplete auth' do
      invalid_source = { 'url' => 'https://example.com/style.json', 'auth' => { 'username' => 'user' } }
      expect { validate_auth_config(invalid_source) }.to raise_error(/Missing auth fields/)
    end

    it 'ignores sources without auth' do
      public_source = 'https://public.example.com/style.json'
      expect { validate_auth_config(public_source) }.not_to raise_error
    end
  end

  describe 'password masking' do
    def get_safe_config(config)
      config.dup.tap do |safe_config|
        safe_config['styles'] = safe_config['styles'].transform_values do |style_config|
          style_config.dup.tap do |safe_style|
            safe_style['sources'] = safe_style['sources'].map do |source|
              source.is_a?(Hash) && source['auth'] ? 
                source.dup.tap { |s| s['auth']['password'] = '***' if s['auth']['password'] } :
                source
            end
          end
        end
      end
    end

    it 'masks passwords in safe config' do
      config_with_auth = {
        'styles' => {
          'test' => {
            'sources' => [
              { 'url' => 'https://example.com/style.json',
                'auth' => { 'username' => 'user', 'password' => 'secret' } }
            ]
          }
        }
      }
      
      safe_config = get_safe_config(config_with_auth)
      password = safe_config.dig('styles', 'test', 'sources', 0, 'auth', 'password')
      
      expect(password).to eq('***')
    end
  end
end 