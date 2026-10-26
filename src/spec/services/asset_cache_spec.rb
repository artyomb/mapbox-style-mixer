require 'spec_helper'
require_relative '../../asset_cache'

RSpec.describe AssetCache do
  it 'preserves the published generation on download or validation failure, including after restart' do
    FakeFS.without do
      Dir.mktmpdir do |root|
        config = { 'styles' => {} }
        cache = described_class.new(config, root: root)
        cache.update(config) { |path| File.write(File.join(path, 'marker'), 'working') }
        expect { cache.update(config) { raise 'upstream unavailable' } }.to raise_error(/unavailable/)
        expect { cache.update('styles' => { 'missing' => {} }) {} }.to raise_error(/not generated/)
        restored = described_class.new({ 'styles' => { 'new' => {} } }, root: root)
        snapshot = restored.checkout
        expect(snapshot.config).to eq(config)
        expect(File.read(File.join(snapshot.root, 'marker'))).to eq('working')
        expect(Dir.glob(File.join(root, 'generation-*')).size).to eq(1)
        restored.release(snapshot)
      end
    end
  end

  it 'keeps at most the working and building generations and waits for old readers before another build' do
    FakeFS.without do
      Dir.mktmpdir do |root|
        cache = described_class.new({ 'styles' => {} }, root: root)
        first = cache.update('styles' => {}) {}
        held = cache.checkout
        second = cache.update('styles' => {}) {}
        expect(File.directory?(first.root)).to be(true)
        expect(File.directory?(second.root)).to be(true)
        started = Queue.new
        attempting = Queue.new
        thread = Thread.new do
          attempting << true
          cache.update('styles' => {}) { started << true }
        end
        Timeout.timeout(5) { attempting.pop }
        expect { Timeout.timeout(0.1) { started.pop } }.to raise_error(Timeout::Error)
        expect(Dir.glob(File.join(root, 'generation-*')).size).to eq(2)
        cache.release(held)
        Timeout.timeout(5) { started.pop }
        third = thread.value
        expect(File.exist?(first.root)).to be(false)
        expect(File.exist?(second.root)).to be(false)
        expect(File.directory?(third.root)).to be(true)
        current = cache.checkout
        expect(current.root).to eq(third.root)
        cache.release(current)
        expect(Dir.glob(File.join(root, 'generation-*')).size).to eq(1)
      end
    end
  end
end
