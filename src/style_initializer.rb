module StyleInitializer
  MUTEX = Mutex.new

  def self.start(config)
    MUTEX.synchronize do
      return false if @thread&.alive?

      $initialization_status = { state: 'loading', progress: 0, message: 'Starting refresh...' }
      @thread = Thread.new { initialize_with_retry(config) }
    end
    true
  end

  def self.initialize_with_retry(config = $config)
    max_retries = 20
    base_delay = 1
    
    (1..max_retries).each do |attempt|
      begin
        LOGGER.info "Starting background initialization (attempt #{attempt}/#{max_retries})..."
        $initialization_status = { state: 'loading', progress: 20, message: 'Downloading source styles...' }
        ASSET_CACHE.update(config) do |root|
          StyleDownloader.new(config, asset_root: root).download_all
          $initialization_status = { state: 'loading', progress: 70, message: 'Mixing styles...' }
          StyleMixer.new(config, asset_root: root).mix_all_styles
        end
        $config = config
        
        $initialization_status = { state: 'ready', progress: 100, message: 'Ready' }
        LOGGER.info "Styles successfully loaded and mixed on startup"
        return
      rescue => e
        $initialization_status = { state: 'error', progress: 0, message: "Error: #{e.message}" }
        
        if attempt == max_retries
          LOGGER.error "Failed to initialize styles after #{max_retries} attempts: #{e.message}"
          return
        end
        
        delay = [base_delay * (2 ** (attempt - 1)), 20].min
        LOGGER.warn "Initialization failed (attempt #{attempt}/#{max_retries}): #{e.message}. Retrying in #{delay}s..."
        sleep(delay)
      end
    end
  end
end
