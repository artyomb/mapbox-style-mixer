module StackServiceBase
  def self.rack_setup(app) = nil
end

class MockLogger
  %w[info debug warn error].each { |method| define_method(method) { |msg| } }
end

LOGGER = MockLogger.new

require 'rspec'
require 'rack/test'
require 'webmock/rspec'
require 'fakefs/spec_helpers'
require 'sinatra'
require 'json'
require 'yaml'

ENV['RACK_ENV'] = 'test'

require_relative '../style_downloader'
require_relative '../style_mixer'
require_relative '../sprite_merger'

$config = {
  'styles' => {
    'test_mix' => {
      'id' => 'test_mix',
      'name' => 'Test Mix Style',
      'sources' => [
        'https://example.com/style1.json',
        'https://example.com/style2.json'
      ]
    }
  }
}

START_TIME = Time.now
$initialization_status = { state: 'ready', progress: 100, message: 'Ready' }

module FixtureHelpers
  def load_fixture(name)
    File.read(File.expand_path("fixtures/#{name}", __dir__))
  end

  def sample_style(id = 'test_style') = {
    'version' => 8, 'name' => 'Test Style', 'id' => id,
    'sources' => { 'test_source' => { 'type' => 'vector', 'url' => 'https://example.com/tiles' } },
    'layers' => [{ 'id' => 'test_layer', 'type' => 'fill', 'source' => 'test_source', 
                   'layout' => { 'text-font' => ['Arial'] } }],
    'sprite' => 'https://example.com/sprite',
    'glyphs' => 'https://example.com/fonts/{fontstack}/{range}.pbf'
  }

  def sample_config = {
    'styles' => {
      'test_mix' => {
        'id' => 'test_mix', 'name' => 'Test Mix Style',
        'sources' => %w[https://example.com/style1.json https://example.com/style2.json]
      }
    }
  }

  def stub_style_request(url, style_data) = 
    stub_request(:get, url).to_return(status: 200, body: style_data.to_json, 
                                     headers: { 'Content-Type' => 'application/json' })

  def stub_sprite_requests(base_url)
    %w[json png].each { |ext| stub_request(:get, "#{base_url}.#{ext}")
                         .to_return(status: 200, body: ext == 'json' ? sample_sprite_json.to_json : 'fake_png_data') }
  end

  def sample_sprite_json = { 'icon1' => { 'width' => 24, 'height' => 24, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 } }
end

RSpec.configure do |config|
  config.include Rack::Test::Methods, FakeFS::SpecHelpers, FixtureHelpers

  config.before(:each) { reset_mocks_and_state }
  config.after(:each) { WebMock.reset! }
end

def reset_mocks_and_state
  WebMock.reset!
  $initialization_status = { state: 'ready', progress: 100, message: 'Ready' }
end

def app = Sinatra::Application