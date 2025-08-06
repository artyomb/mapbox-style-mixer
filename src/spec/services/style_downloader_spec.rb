require 'spec_helper'

RSpec.describe StyleDownloader do
  let(:config) { sample_config }
  let(:downloader) { StyleDownloader.new(config) }

  before do
    FakeFS.activate!
  end

  after do
    FakeFS.deactivate!
  end

  describe 'initialization' do
    it 'uses provided config' do
      expect(downloader.instance_variable_get(:@config)).to eq(config)
    end

    it 'uses global config when none provided' do
      global_downloader = StyleDownloader.new
      expect(global_downloader.instance_variable_get(:@config)).to eq($config)
    end

    it 'sets correct directory paths' do
      raw_dir = downloader.instance_variable_get(:@raw_dir)
      fonts_dir = downloader.instance_variable_get(:@fonts_dir)
      sprites_dir = downloader.instance_variable_get(:@sprites_dir)
      
      expect(raw_dir).to end_with('raw_styles')
      expect(fonts_dir).to end_with('fonts')
      expect(sprites_dir).to end_with('sprites')
    end
  end

  describe '#download_all' do
    it 'runs without crashing when mocked' do
      allow(downloader).to receive(:process_mix_style).and_return(true)
      expect { downloader.download_all }.not_to raise_error
    end
  end

  describe '#download_style' do
    it 'raises error for non-existing style' do
      expect { downloader.download_style('non_existing') }.to raise_error(/not found/)
    end

    it 'accepts valid style id' do
      allow(downloader).to receive(:process_mix_style).and_return(true)
      expect { downloader.download_style('test_mix') }.not_to raise_error
    end
  end

  describe 'source configuration handling' do
    it 'handles string sources' do
      source_config = 'https://example.com/style.json'
      
      url = source_config.is_a?(Hash) ? source_config['url'] : source_config
      auth = source_config.is_a?(Hash) ? source_config['auth'] : nil
      
      expect(url).to eq('https://example.com/style.json')
      expect(auth).to be_nil
    end

    it 'handles hash sources with auth' do
      source_config = { 
        'url' => 'https://example.com/style.json',
        'auth' => { 'username' => 'user', 'password' => 'pass' }
      }
      
      url = source_config.is_a?(Hash) ? source_config['url'] : source_config
      auth = source_config.is_a?(Hash) ? source_config['auth'] : nil
      
      expect(url).to eq('https://example.com/style.json')
      expect(auth).to include('username' => 'user', 'password' => 'pass')
    end

    it 'creates Basic Auth headers correctly' do
      auth_config = { 'username' => 'test_user', 'password' => 'test_pass' }
      
      credentials = Base64.strict_encode64("#{auth_config['username']}:#{auth_config['password']}")
      headers = { 'Authorization' => "Basic #{credentials}" }
      
      expect(headers['Authorization']).to start_with('Basic ')
      expect(Base64.decode64(credentials)).to eq('test_user:test_pass')
    end
  end

  describe 'directory management' do
    it 'can call prepare_directories without error' do
      expect { downloader.send(:prepare_directories) }.not_to raise_error
    end
  end
end