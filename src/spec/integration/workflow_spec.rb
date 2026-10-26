require 'spec_helper'
require_relative '../support/service_runtime'

RSpec.describe 'Service runtime' do
  it 'boots Falcon, downloads and serves a mixed style, and refreshes it' do
    FakeFS.without do
      WebMock.disable_net_connect!(allow_localhost: true)
      runtime = ServiceRuntime.new
      begin
        runtime.start
        health = runtime.get('/healthcheck')
        expect(health.code).to eq('200')
        expect(JSON.parse(health.body)).to eq('Status' => 'Healthy')

        response = runtime.get('/styles/test_mix')
        expect(response.code).to eq('200')
        style = JSON.parse(response.body)
        expect(style.fetch('sources').keys).to eq(['fixture_land'])
        expect(style.fetch('layers').first).to include('id' => 'fixture_land', 'source' => 'fixture_land')
        expect(style.fetch('glyphs')).to match(%r{\Ahttp://127\.0\.0\.1:\d+/fonts/})
        expect(runtime.source_requests.size).to eq(1)
        expect(runtime.get('/').code).to eq('200')
        expect(runtime.get('/map?style=test_mix').code).to eq('200')
        expect(runtime.get('/styles/missing').code).to eq('404')

        expect(runtime.get('/refresh').code).to eq('302')
        runtime.wait_until_ready
        expect(runtime.source_requests.size).to eq(2)
        expect(runtime.get('/styles/test_mix').code).to eq('200')
      ensure
        runtime.stop
        WebMock.disable_net_connect!
      end
    end
  end
end
