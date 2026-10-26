require 'fileutils'
require 'net/http'
require 'socket'
require 'tempfile'
require 'timeout'
require 'tmpdir'
require 'rbconfig'
require 'base64'
require 'zlib'
require_relative '../../glyph_pbf'

class ServiceRuntime
  attr_reader :source_requests
  attr_accessor :source_mode, :glyph_mode, :version

  def start(auth: nil, string_source: false, glyphs: false, sprites: false)
    @directory = Dir.mktmpdir('style-mixer-spec-')
    @upstream = TCPServer.new('127.0.0.1', 0)
    @authorization = auth && "Basic #{Base64.strict_encode64("#{auth['username']}:#{auth['password']}")}"
    @glyphs, @sprites = glyphs, sprites
    @source_mode, @glyph_mode, @version = :valid, :valid, 1
    @source_requests = Queue.new
    @upstream_thread = Thread.new { serve_source }
    source_root = File.expand_path('../..', __dir__)
    files = Dir.glob("#{source_root}/*.{rb,ru}") + %w[views public .version].map { |name| File.join(source_root, name) }
    FileUtils.cp_r(files, @directory)
    source_url = "http://127.0.0.1:#{@upstream.addr[1]}/style.json"
    source = { 'url' => source_url, 'prefix' => 'fixture' }
    source['auth'] = auth if auth
    sources = [string_source ? source_url : source]
    sources << { 'url' => source_url.sub('style.json', 'fallback-style.json'), 'prefix' => 'fallback' } if glyphs
    config = { 'styles' => { 'test_mix' => {
      'name' => 'Runtime Test Style',
      'sources' => sources
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
    wait_for_state('ready')
  end

  def wait_for_state(state, allow_errors: false)
    Timeout.timeout(20) do
      loop do
        begin
          response = get('/status')
          status = JSON.parse(response.body) if response.code == '200'
          return status if status && status['state'] == state
          raise "Initialization failed: #{status['message']}" if !allow_errors && state == 'ready' && status && status['state'] == 'error'
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
          # Falcon may still be binding its listening socket.
        end
        sleep 0.05
      end
    end
  rescue StandardError => error
    raise "#{error.message}\nService log:\n#{File.read(@log.path)}"
  end

  def pause_next_source
    @source_gate = { started: Queue.new, release: Queue.new }
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
      request_line = client.gets
      headers = {}
      while (line = client.gets) && !line.strip.empty?
        name, value = line.split(':', 2)
        headers[name.downcase] = value.strip
      end
      target = request_line.split[1]
      if target.end_with?('style.json')
        @source_requests << { target: target, headers: headers }
        if (gate = @source_gate)
          @source_gate = nil
          gate[:started] << true
          gate[:release].pop
        end
      end
      status, content_type, body = source_response(target)
      if status == 'disconnect'
        client.close
        next
      end
      status = '401 Unauthorized' if @authorization && target == '/style.json' && headers['authorization'] != @authorization
      client.write("HTTP/1.1 #{status}\r\nContent-Type: #{content_type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
    end
  rescue IOError, Errno::EBADF
    nil
  ensure
    client&.close
  end

  def source_response(target)
    if target.start_with?('/glyphs/')
      return ['disconnect', nil, nil] if target.include?('/primary/') && @glyph_mode == :disconnect
      range = File.basename(target, '.pbf')
      body = glyph_body(range)
      if target.include?('/primary/')
        body = { html: '<html>upstream error</html>', json: '{"error":"upstream error"}',
                 invalid_wire: "\x0f".b, truncated: "\x0a\x05\x0a".b }.fetch(@glyph_mode, body)
      end
      return ['200 OK', 'application/octet-stream', body]
    end
    if target.start_with?('/sprite')
      size = target.include?('@2x') ? 2 : 1
      body = target.end_with?('.png') ? png(size) : { 'point' => { 'width' => size, 'height' => size, 'x' => 0, 'y' => 0, 'pixelRatio' => size } }.to_json
      return ['200 OK', target.end_with?('.png') ? 'image/png' : 'application/json', body]
    end
    return ['503 Service Unavailable', 'application/json', '{}'] if @source_mode == :failure

    style = {
      'version' => 8, 'id' => 'fixture_source',
      'sources' => { 'land' => { 'type' => 'vector', 'url' => 'https://example.test/tiles.json' } },
      'layers' => [{ 'id' => @version == 1 ? 'land' : 'updated', 'type' => 'fill', 'source' => 'land', 'source-layer' => 'land' }]
    }
    if @glyphs
      style['glyphs'] = "http://127.0.0.1:#{@upstream.addr[1]}/glyphs/primary/{fontstack}/{range}.pbf"
      style['layers'] << { 'id' => 'label', 'type' => 'symbol', 'source' => 'land', 'source-layer' => 'land', 'layout' => { 'text-field' => 'A', 'text-font' => ['Fixture Font'] } }
    end
    style['sprite'] = "http://127.0.0.1:#{@upstream.addr[1]}/sprite" if @sprites
    if target == '/fallback-style.json'
      style = { 'version' => 8, 'id' => 'fallback', 'sources' => {}, 'layers' => [],
                'glyphs' => "http://127.0.0.1:#{@upstream.addr[1]}/glyphs/alternative/{fontstack}/{range}.pbf" }
    end
    style['sources']['land'] = nil if @source_mode == :invalid_mix
    ['200 OK', 'application/json', style.to_json]
  end

  def glyph_body(range)
    glyphs = range == '0-255' ? [GlyphPbf::Glyph.new(id: 65, width: 1, height: 1, left: 0, top: 0, advance: @version,
                                                  bitmap: @version.chr.b * 49)] : []
    GlyphPbf::Message.encode(GlyphPbf::Message.new(stacks: [GlyphPbf::Fontstack.new(name: 'Fixture Font', range: range, glyphs: glyphs)]))
  end

  def png(size)
    chunk = ->(type, bytes) { [bytes.bytesize].pack('N') + type + bytes + [Zlib.crc32(type + bytes)].pack('N') }
    header = [size, size, 8, 6, 0, 0, 0].pack('NNCCCCC')
    pixels = ("\x00".b + [@version, 0, 0, 255].pack('C*') * size) * size
    "\x89PNG\r\n\x1a\n".b + chunk.call('IHDR', header) + chunk.call('IDAT', Zlib.deflate(pixels)) + chunk.call('IEND', ''.b)
  end
end
