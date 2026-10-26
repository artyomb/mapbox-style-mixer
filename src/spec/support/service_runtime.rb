require 'fileutils'
require 'net/http'
require 'socket'
require 'tempfile'
require 'timeout'
require 'tmpdir'
require 'rbconfig'

class ServiceRuntime
  attr_reader :source_requests

  def start
    @directory = Dir.mktmpdir('style-mixer-spec-')
    @upstream = TCPServer.new('127.0.0.1', 0)
    @source_requests = Queue.new
    @upstream_thread = Thread.new { serve_source }
    source_root = File.expand_path('../..', __dir__)
    files = Dir.glob("#{source_root}/*.{rb,ru}") + %w[views public .version].map { |name| File.join(source_root, name) }
    FileUtils.cp_r(files, @directory)
    config = { 'styles' => { 'test_mix' => {
      'name' => 'Runtime Test Style',
      'sources' => [{ 'url' => "http://127.0.0.1:#{@upstream.addr[1]}/style.json", 'prefix' => 'fixture' }]
    } } }
    config_path = File.join(@directory, 'styles_config.yaml')
    File.write(config_path, config.to_yaml)
    @port = TCPServer.open('127.0.0.1', 0) { |server| server.addr[1] }
    @log = Tempfile.new('style-mixer-runtime-')
    environment = {
      'BUNDLE_GEMFILE' => File.join(source_root, 'Gemfile'),
      'CONFIG_PATH' => config_path,
      'RACK_ENV' => 'test',
      'NO_RT_DEBUG' => '1',
      'OTEL_EXPORTER_OTLP_ENDPOINT' => nil,
      'SWARM_NATS_URL' => nil
    }
    @pid = Process.spawn(environment, RbConfig.ruby, '-S', 'bundle', 'exec', 'rackup',
                         '-o', '127.0.0.1', '-p', @port.to_s, '-s', 'falcon',
                         chdir: @directory, out: @log.path, err: @log.path, pgroup: true)
    wait_until_ready
    self
  rescue StandardError
    stop
    raise
  end

  def get(path)
    Net::HTTP.start('127.0.0.1', @port, nil, open_timeout: 1, read_timeout: 2) { |http| http.get(path) }
  end

  def wait_until_ready
    Timeout.timeout(20) do
      loop do
        begin
          response = get('/status')
          status = JSON.parse(response.body) if response.code == '200'
          return if status && status['state'] == 'ready'
          raise "Initialization failed: #{status['message']}" if status && status['state'] == 'error'
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
          # Falcon may still be binding its listening socket.
        end
        sleep 0.05
      end
    end
  rescue StandardError => error
    raise "#{error.message}\nService log:\n#{File.read(@log.path)}"
  end

  def stop
    if @pid
      begin
        Process.kill('TERM', -@pid)
        Timeout.timeout(5) { Process.wait(@pid) }
      rescue Timeout::Error
        Process.kill('KILL', -@pid)
        Process.wait(@pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
    @upstream&.close
    @upstream_thread&.join(2)
    @upstream_thread&.kill if @upstream_thread&.alive?
    @log&.close!
    FileUtils.remove_entry(@directory) if @directory && Dir.exist?(@directory)
    @pid = nil
  end

  private

  def serve_source
    client = nil
    loop do
      client = @upstream.accept
      @source_requests << client.gets
      loop { break if client.gets.to_s.strip.empty? }
      body = {
        'version' => 8, 'id' => 'fixture_source',
        'sources' => { 'land' => { 'type' => 'vector', 'url' => 'https://example.test/tiles.json' } },
        'layers' => [{ 'id' => 'land', 'type' => 'fill', 'source' => 'land', 'source-layer' => 'land' }]
      }.to_json
      client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
    end
  rescue IOError, Errno::EBADF
    nil
  ensure
    client&.close
  end
end
