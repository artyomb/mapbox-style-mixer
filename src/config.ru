require 'sinatra'
require 'yaml'
require 'json'
require 'faraday'
require 'stack-service-base'
require 'slim'

StackServiceBase.rack_setup self

enable :sessions

CONFIG = YAML.load_file(File.expand_path('styles_config.yaml', __dir__))
START_TIME = Time.now

helpers do
  def fetch_style(mix_id)
    mix_config = CONFIG['styles'][mix_id]
    halt 404, { error: "Style '#{mix_id}' not found" }.to_json unless mix_config
    
    source_url = mix_config['sources'].first
    resp = Faraday.get(source_url)
    raise "Failed to fetch #{source_url}" unless resp.success?
    JSON.parse(resp.body)
  end
  
  def get_styles_data
    CONFIG['styles'].keys.map do |style_id|
      {
        id: style_id,
        name: CONFIG['styles'][style_id]['name'],
        endpoint: "/styles/#{style_id}",
        sources_count: CONFIG['styles'][style_id]['sources'].length
      }
    end
  end
end

get '/' do
  @styles = get_styles_data
  @total_sources = @styles.sum { |s| s[:sources_count] }
  @uptime = Time.now - START_TIME
  @refresh_message = session[:refresh_message]
  session.delete(:refresh_message)
  slim :index
end

get '/api/styles' do
  content_type :json
  {
    available_styles: get_styles_data
  }.to_json
end

get '/styles/:style' do
  content_type :json
  fetch_style(params[:style]).to_json
end

get '/refresh' do
  begin
    session[:refresh_message] = { success: true, message: "Стили успешно обновлены" }
  rescue => e
    session[:refresh_message] = { success: false, message: "Ошибка обновления: #{e.message}" }
  end
  redirect '/'
end

run Sinatra::Application