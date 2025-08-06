require 'spec_helper'

RSpec.describe StyleMixer do
  let(:config) { sample_config }
  let(:mixer) { StyleMixer.new(config) }
  
  before do
    FakeFS.activate!
  end

  after do
    FakeFS.deactivate!
  end

  describe 'initialization' do
    it 'uses provided config' do
      expect(mixer.instance_variable_get(:@config)).to eq(config)
    end

    it 'uses global config when none provided' do
      global_mixer = StyleMixer.new
      expect(global_mixer.instance_variable_get(:@config)).to eq($config)
    end

    it 'sets up correct instance variables' do
      expect(mixer.instance_variable_get(:@config)).to be_a(Hash)
    end
  end

  describe '#mix_all_styles' do
    it 'runs without errors when mocked' do
      allow(mixer).to receive(:mix_styles).and_return(true)
      expect { mixer.mix_all_styles }.not_to raise_error
    end

    it 'processes styles from config' do
      expect(mixer).to receive(:mix_styles).at_least(:once)
      mixer.mix_all_styles
    end

    it 'handles errors gracefully' do
      allow(mixer).to receive(:mix_styles).and_raise(StandardError.new('Test error'))
      expect { mixer.mix_all_styles }.not_to raise_error
    end
  end

  describe '#mix_styles method signature' do
    it 'accepts two arguments' do
      mix_config = config['styles']['test_mix']
      
      allow(mixer).to receive(:load_raw_styles).and_return([])
      allow(mixer).to receive(:create_mixed_style).and_return({})
      allow(mixer).to receive(:save_mixed_style).and_return(true)
      
      expect { mixer.mix_styles('test_mix', mix_config) }.not_to raise_error
    end

    it 'requires both mix_id and mix_config' do
      expect { mixer.mix_styles('test_mix') }.to raise_error(ArgumentError)
    end
  end

  describe 'style file processing' do
    it 'handles empty styles gracefully' do
      empty_config = { 'styles' => {} }
      empty_mixer = StyleMixer.new(empty_config)
      
      expect { empty_mixer.mix_all_styles }.not_to raise_error
    end

    it 'processes valid style structure' do
      basic_style = sample_style
      
      expect(basic_style).to have_key('version')
      expect(basic_style).to have_key('sources')
      expect(basic_style).to have_key('layers')
      expect(basic_style['version']).to eq(8)
    end
  end
end