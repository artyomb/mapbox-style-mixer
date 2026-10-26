require 'spec_helper'
require_relative '../support/service_runtime'

RSpec.describe 'Service runtime' do
  it 'downloads an authenticated source without exposing credentials and refreshes the mixed style' do
    FakeFS.without do
      WebMock.disable_net_connect!(allow_localhost: true)
      runtime = ServiceRuntime.new
      begin
        auth = { 'username' => 'fixture_user', 'password' => 'fixture_secret' }
        runtime.start(auth: auth)
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
        source_request = runtime.source_requests.pop
        expect(source_request[:target]).to eq('/style.json')
        expect(source_request[:headers]['authorization']).to eq("Basic #{Base64.strict_encode64('fixture_user:fixture_secret')}")
        styles_response = runtime.get('/styles')
        expect(styles_response.code).to eq('200')
        public_config = JSON.parse(styles_response.body).fetch('available_styles').first
        expect(public_config.dig('sources', 0, 'auth', 'password')).to eq('***')
        expect(public_config.dig('config', 'sources', 0, 'auth', 'password')).to eq('***')
        expect(styles_response.body).not_to include(auth.fetch('password'))
        expect(runtime.get('/').code).to eq('200')
        expect(runtime.get('/map?style=test_mix').code).to eq('200')
        expect(runtime.get('/styles/missing').code).to eq('404')

        expect(runtime.get('/refresh').code).to eq('302')
        runtime.wait_until_ready
        expect(runtime.source_requests.size).to eq(1)
        expect(runtime.source_requests.pop[:headers]['authorization']).to eq(source_request[:headers]['authorization'])
        expect(runtime.get('/styles/test_mix').code).to eq('200')
      ensure
        runtime.stop
        WebMock.disable_net_connect!
      end
    end
  end

  it 'downloads and serves a style configured with a plain source URL' do
    FakeFS.without do
      WebMock.disable_net_connect!(allow_localhost: true)
      runtime = ServiceRuntime.new
      begin
        runtime.start(string_source: true)
        response = runtime.get('/styles/test_mix')
        expect(response.code).to eq('200')
        style = JSON.parse(response.body)
        expect(style.fetch('sources').keys).to eq(['fixture_source_land'])
        expect(style.fetch('layers').first).to include('source' => 'fixture_source_land')
        expect(runtime.source_requests.pop[:target]).to eq('/style.json')
      ensure
        runtime.stop
        WebMock.disable_net_connect!
      end
    end
  end

  it 'keeps working assets during failed or concurrent refreshes and publishes a complete replacement' do
    FakeFS.without do
      WebMock.disable_net_connect!(allow_localhost: true)
      runtime = ServiceRuntime.new
      begin
        runtime.start(glyphs: true, sprites: true)
        original = runtime.get('/styles/test_mix')
        style = JSON.parse(original.body)
        glyph_url = URI(style.fetch('glyphs').sub('{fontstack}', 'fixture/Fixture%20Font').sub('{range}', '0-255'))
        glyph = runtime.get(glyph_url.request_uri)
        sprite_url = URI(style.fetch('sprite'))
        sprite_url.path += '.png'
        sprite = runtime.get(sprite_url.request_uri)
        expect(glyph.code).to eq('200')
        expect(GlyphPbf.validate!(glyph.body)).to be(true)
        expect(sprite.code).to eq('200')
        expect(JSON.parse(runtime.get('/fonts.json').body)).to include('fixture/Fixture Font')
        expect(runtime.get('/fonts/fixture/missing/0-255.pbf').code).to eq('404')

        empty_range = runtime.get(glyph_url.request_uri.sub('0-255', '256-511'))
        expect(empty_range.code).to eq('200')
        expect(GlyphPbf::Message.decode(empty_range.body).stacks.first.glyphs).to be_empty

        runtime.source_mode = :failure
        gate = runtime.pause_next_source
        expect(runtime.get('/refresh').code).to eq('302')
        Timeout.timeout(5) { gate[:started].pop }
        2.times { expect(runtime.get('/refresh').code).to eq('302') }
        expect(runtime.get('/styles/test_mix').body).to eq(original.body)
        expect(runtime.get(glyph_url.request_uri).body).to eq(glyph.body)
        expect(runtime.get(sprite_url.request_uri).body).to eq(sprite.body)
        gate[:release] << true
        runtime.wait_for_state('error')
        expect(runtime.get('/styles/test_mix').body).to eq(original.body)
        expect(runtime.get(glyph_url.request_uri).body).to eq(glyph.body)
        expect(runtime.get(sprite_url.request_uri).body).to eq(sprite.body)

        runtime.version = 2
        runtime.source_mode = :valid
        runtime.wait_for_state('ready', allow_errors: true)
        updated = runtime.get('/styles/test_mix')
        new_style = JSON.parse(updated.body)
        expect(new_style.fetch('layers').first.fetch('id')).to eq('fixture_updated')
        expect(new_style.fetch('glyphs')).to eq(style.fetch('glyphs'))
        new_glyph_url = URI(new_style.fetch('glyphs').sub('{fontstack}', 'fixture/Fixture%20Font').sub('{range}', '0-255'))
        new_glyph = runtime.get(new_glyph_url.request_uri)
        expect(GlyphPbf::Message.decode(new_glyph.body).stacks.first.glyphs.first.advance).to eq(2)
        expect(runtime.get(glyph_url.request_uri).body).to eq(new_glyph.body)
        expect(runtime.get(sprite_url.request_uri).body).not_to eq(sprite.body)
        expect(runtime.source_requests.size).to eq(5)

        runtime.source_mode = :invalid_mix
        expect(runtime.get('/refresh').code).to eq('302')
        runtime.wait_for_state('error')
        expect(runtime.get('/styles/test_mix').body).to eq(updated.body)
        expect(runtime.get(new_glyph_url.request_uri).body).to eq(new_glyph.body)
      ensure
        runtime.stop
        WebMock.disable_net_connect!
      end
    end
  end

  it 'uses another glyph source when the first returns HTML, JSON, damaged PBF or a connection failure' do
    FakeFS.without do
      WebMock.disable_net_connect!(allow_localhost: true)
      runtime = ServiceRuntime.new
      begin
        runtime.start(glyphs: true)
        %i[html json invalid_wire truncated disconnect].each do |mode|
          runtime.glyph_mode = mode
          expect(runtime.get('/refresh').code).to eq('302')
          runtime.wait_until_ready
          style = JSON.parse(runtime.get('/styles/test_mix').body)
          glyph_url = URI(style.fetch('glyphs').sub('{fontstack}', 'fixture/Fixture%20Font').sub('{range}', '0-255'))
          response = runtime.get(glyph_url.request_uri)
          expect(response.code).to eq('200')
          expect(GlyphPbf.validate!(response.body)).to be(true)
        end
      ensure
        runtime.stop
        WebMock.disable_net_connect!
      end
    end
  end
end
