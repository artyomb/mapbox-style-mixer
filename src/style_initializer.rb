module StyleInitializer
  def self.initialize_with_retry
    max_retries = 20
    base_delay = 1
    
    (1..max_retries).each do |attempt|
      begin
        LOGGER.info "Starting background initialization (attempt #{attempt}/#{max_retries})..."
        $initialization_status = { state: 'loading', progress: 20, message: 'Downloading source styles...' }
        StyleDownloader.new($config).download_all
        
        $initialization_status = { state: 'loading', progress: 70, message: 'Mixing styles...' }
        StyleMixer.new($config).mix_all_styles
        
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
