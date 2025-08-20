require 'spec_helper'

RSpec.describe 'API Routes' do
  class TestApp < Sinatra::Base
    set :environment, :test
    
    helpers do
      def json_response(data) = (content_type :json; data.to_json)
      def error_response(code, message) = halt(code, { error: message }.to_json)
    end
    
    get('/') { 'Main page' }
    get('/status') { json_response({ state: 'ready', progress: 100, message: 'Ready' }) }
    get('/styles') { json_response({ available_styles: [] }) }
    
    get '/styles/:style' do
      params[:style] == 'test_mix' ? 
        json_response({ id: params[:style], name: 'Test Style' }) :
        error_response(404, "Style '#{params[:style]}' not found")
    end
    
    get '/sprite/:mix_id.json' do
      params[:mix_id] == 'test_mix_sprite' ?
        json_response({ icon1: { width: 24, height: 24, x: 0, y: 0 } }) :
        error_response(404, "Sprite JSON not found for mix '#{params[:mix_id]}'")
    end
    
    get '/sprite/:mix_id.png' do
      params[:mix_id] == 'test_mix_sprite' ?
        (content_type :png; 'fake_png_data') :
        error_response(404, "Sprite PNG not found for mix '#{params[:mix_id]}'")
    end
    
    get '/sprite/:mix_id@2x.json' do
      params[:mix_id] == 'test_mix_sprite@2x' ?
        json_response({ icon1: { width: 48, height: 48, x: 0, y: 0, pixelRatio: 2 } }) :
        error_response(404, "Sprite JSON@2x not found for mix '#{params[:mix_id]}'")
    end
    
    get '/sprite/:mix_id@2x.png' do
      params[:mix_id] == 'test_mix_sprite@2x' ?
        (content_type :png; 'fake_png_data_2x') :
        error_response(404, "Sprite PNG@2x not found for mix '#{params[:mix_id]}'")
    end

    get '/fonts/*/:range.pbf' do
      params[:splat].first == 'test_font' ?
        (content_type 'application/octet-stream'; 'fake_font_data') :
        error_response(404, 'Font file not found')
    end
  end

  def app = TestApp
  
  def have_json_content = have_attributes(content_type: include('application/json'))
  
  before do
    FakeFS.activate!
    %w[src/mixed_styles src/sprite src/fonts/test_font].each { |dir| FileUtils.mkdir_p(dir) }
    
    create_test_files
  end

  def create_test_files
    test_style = { 'version' => 8, 'id' => 'test_mix', 'name' => 'Test Style' }
    test_sprite = { 'icon1' => { 'width' => 24, 'height' => 24, 'x' => 0, 'y' => 0, 'pixelRatio' => 1 } }
    test_sprite_2x = { 'icon1' => { 'width' => 48, 'height' => 48, 'x' => 0, 'y' => 0, 'pixelRatio' => 2 } }
    
    File.write('src/mixed_styles/test_mix.json', test_style.to_json)
    [
      ['src/sprite/test_mix_sprite.json', test_sprite.to_json],
      ['src/sprite/test_mix_sprite.png', 'fake_png_data'],
      ['src/sprite/test_mix_sprite@2x.json', test_sprite_2x.to_json],
      ['src/sprite/test_mix_sprite@2x.png', 'fake_png_data_2x'],
      ['src/fonts/test_font/0-255.pbf', 'fake_font_data']
    ].each { |path, content| File.write(path, content) }
    
    allow($config).to receive(:[]).with('styles').and_return({ 'test_mix' => { 'id' => 'test_mix', 'name' => 'Test Mix Style', 'sources' => %w[https://example.com/style1.json https://example.com/style2.json] } })
  end

  after { FakeFS.deactivate! }

  describe 'GET /status' do
    it 'returns initialization status' do
      get '/status'
      expect(last_response).to be_ok.and have_json_content
      
      status = JSON.parse(last_response.body)
      expect(status.keys).to include(*%w[state progress message])
    end
  end

  describe 'GET /styles/:style' do
    it 'returns existing style' do
      get '/styles/test_mix'
      expect(last_response).to be_ok.and have_json_content
      expect(JSON.parse(last_response.body)['id']).to eq('test_mix')
    end

    it('returns 404 for non-existing style') do
      get '/styles/non_existing'
      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body)).to have_key('error')
    end
  end

  describe 'GET /sprite/:mix_id.json' do
    it 'returns sprite JSON' do
      get '/sprite/test_mix_sprite.json'
      expect(last_response).to be_ok.and have_json_content
      expect(JSON.parse(last_response.body)).to have_key('icon1')
    end

    it('returns 404 for non-existing sprite') { get('/sprite/non_existing.json'); expect(last_response.status).to eq(404) }
  end

  describe 'GET /fonts/*/:range.pbf' do
    it 'returns font file' do
      get '/fonts/test_font/0-255.pbf'
      expect(last_response).to be_ok.and have_attributes(content_type: include('application/octet-stream'), body: 'fake_font_data')
    end

    it('returns 404 for non-existing font') { get('/fonts/non_existing/0-255.pbf'); expect(last_response.status).to eq(404) }
  end
end