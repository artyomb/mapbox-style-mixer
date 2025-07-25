require 'yaml'
require 'json'
require 'fileutils'
require 'faraday'
require 'uri'
require 'parallel'

config = YAML.load_file(File.expand_path('styles_to_mix.yml', __dir__))
raw_dir = File.expand_path('raw_styles', __dir__)
fonts_dir = File.expand_path('fonts', __dir__)
sprites_dir = File.expand_path('sprites', __dir__)

FileUtils.mkdir_p(raw_dir)
FileUtils.mkdir_p(fonts_dir)
FileUtils.mkdir_p(sprites_dir)

config['styles'].each do |style|
  name = style['name']
  url = style['url']
  next unless url
  json_path = File.join(raw_dir, "#{name}.json")
  resp = Faraday.get(url)
  raise "Failed to fetch #{url}" unless resp.success?
  File.write(json_path, resp.body)
  style_json = JSON.parse(resp.body)

  if (sprite_url = style_json['sprite'])
    dir = File.join(sprites_dir, name)
    FileUtils.mkdir_p(dir)
    %w[json png].each do |ext|
      r = Faraday.get("#{sprite_url}.#{ext}")
      File.write(File.join(dir, "sprite.#{ext}"), r.body) if r.success?
    end
  end

  next unless (glyphs_url = style_json['glyphs'])
  fontstacks = style_json['layers'].map { |l| l.dig('layout', 'text-font') }.compact.flatten.uniq
  ranges = (0..65535).step(256).map { |start| "#{start}-#{start+255}" }
  tasks = fontstacks.product(ranges)
  Parallel.each(tasks, in_threads: 8) do |fontstack, range|
    dir = File.join(fonts_dir, fontstack)
    FileUtils.mkdir_p(dir)
    enc = URI.encode_www_form_component(fontstack)
    fname = "#{range}.pbf"
    url1 = glyphs_url.sub('{fontstack}', enc).sub('{range}', range)
    url1 += '.pbf' unless url1.end_with?('.pbf')
    r = Faraday.get(url1)
    unless r.success?
      url2 = "https://demotiles.maplibre.org/font/#{enc}/#{fname}"
      r = Faraday.get(url2)
    end
    puts "GET #{url1} => #{r.status}#{' (fallback)' unless r.success?}"
    File.write(File.join(dir, fname), r.body) if r.success?
  end
end 