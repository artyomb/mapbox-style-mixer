require 'fileutils'
require 'json'
require 'tmpdir'
require 'set'

class AssetCache
  DIRECTORIES = %w[raw_styles mixed_styles fonts sprites sprite].freeze
  Snapshot = Data.define(:root, :config)

  def initialize(config, root: File.expand_path('cache', __dir__), legacy_root: __dir__)
    @root = root
    @link = File.join(root, 'current')
    @mutex = Mutex.new
    @writer_mutex = Mutex.new
    @released = ConditionVariable.new
    @legacy_root = legacy_root
    @readers = Hash.new(0)
    @obsolete = Set.new
    @current = if File.exist?(@link)
      current_root = File.realpath(@link)
      Snapshot.new(current_root, JSON.parse(File.read(File.join(current_root, 'config.json'))))
    else
      Snapshot.new(legacy_root, config)
    end
    prune
  end

  def checkout
    @mutex.synchronize do
      @readers[@current.root] += 1
      @current
    end
  end

  def release(snapshot)
    return unless snapshot

    @mutex.synchronize do
      @readers[snapshot.root] -= 1
      retire(snapshot.root) if @readers[snapshot.root].zero? && @obsolete.include?(snapshot.root)
    end
  rescue StandardError => error
    LOGGER.warn "Failed to remove retired assets: #{error.message}"
  end

  def update(config)
    @writer_mutex.synchronize do
      @mutex.synchronize do
        until @obsolete.empty?
          @obsolete.to_a.each { |root| retire(root) }
          @released.wait(@mutex) unless @obsolete.empty?
        end
      end
      build(config) { |root| yield root }
    end
  end

  private

  def build(config)
    FileUtils.mkdir_p(@root)
    root = Dir.mktmpdir('generation-', @root)
    id = File.basename(root)
    temporary_link = File.join(@root, ".current-#{id}")
    published = false
    begin
      yield root
      validate(root, config)
      File.open(File.join(root, 'config.json'), 'w', 0o600) { |file| file.write(JSON.generate(config)) }
      snapshot = Snapshot.new(root, config)
      @mutex.synchronize do
        previous = @current
        File.symlink(id, temporary_link)
        File.rename(temporary_link, @link)
        published = true
        @current = snapshot
        prune(previous.root)
      end
      snapshot
    ensure
      File.unlink(temporary_link) if File.symlink?(temporary_link)
      FileUtils.rm_rf(root) unless published
    end
  end

  def validate(root, config)
    config.fetch('styles').each_key do |id|
      path = File.join(root, 'mixed_styles', "#{id}.json")
      raise "Mixed style '#{id}' was not generated" unless File.file?(path)

      style = JSON.parse(File.read(path))
      unless style['version'] == 8 && style['sources'].is_a?(Hash) && style['layers'].is_a?(Array)
        raise "Invalid mixed style '#{id}'"
      end
      inputs = Dir.glob(File.join(root, 'raw_styles', "#{id}_*.json"))
      sprites_expected = inputs.any? do |input|
        source = JSON.parse(File.read(input))
        source['sprite'].is_a?(String) && !source['sprite'].empty? || source['sprites'].is_a?(Array) && source['sprites'].any?
      end
      raise "Sprites for '#{id}' were not generated" if sprites_expected && !style['sprite']
      next unless style['sprite']

      ['', '@2x'].product(%w[json png]).each do |suffix, extension|
        sprite = File.join(root, 'sprite', "#{id}_sprite#{suffix}.#{extension}")
        raise "Missing sprite for '#{id}': #{suffix}.#{extension}" unless File.file?(sprite)
        JSON.parse(File.read(sprite)) if extension == 'json'
      end
    end
  end

  def prune(previous = nil)
    roots = Dir.glob(File.join(@root, 'generation-*')).select { |path| File.directory?(path) }
    roots << previous if previous == @legacy_root
    @obsolete.merge(roots - [@current.root])
    @obsolete.to_a.each { |root| retire(root) }
  rescue StandardError => error
    LOGGER.warn "Failed to prune old asset generations: #{error.message}"
  end

  def retire(root)
    @obsolete.add(root)
    return unless @readers[root].zero?

    @released.broadcast
    remove(root)
    @obsolete.delete(root)
  end

  def remove(root)
    paths = root == @legacy_root ? DIRECTORIES.map { |name| File.join(root, name) } : [root]
    paths.each { |path| FileUtils.remove_entry(path) if File.exist?(path) || File.symlink?(path) }
    @readers.delete(root)
  end
end
