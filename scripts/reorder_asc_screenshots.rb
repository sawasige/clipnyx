#!/usr/bin/env ruby
# ASC 上のスクリーンショット表示順をファイル名順（1_, 2_, ...）に直す。
# fastlane deliver は並列アップロードのため表示順が完了順になることがある。
#
# 使い方: ruby scripts/reorder_asc_screenshots.rb <versionString>
# 例:     ruby scripts/reorder_asc_screenshots.rb 1.4.0
require 'jwt'
require 'json'
require 'net/http'
require 'uri'
require 'openssl'

version = ARGV[0] or abort "usage: #{$0} <versionString>"
APP_ID = '6759652985'

cfg = JSON.parse(File.read(File.expand_path('../fastlane/api_key.json', __dir__)))
key = OpenSSL::PKey::EC.new(cfg['key'])
now = Time.now.to_i
TOKEN = JWT.encode(
  { iss: cfg['issuer_id'], iat: now, exp: now + 1000, aud: 'appstoreconnect-v1' },
  key, 'ES256', { kid: cfg['key_id'], typ: 'JWT' }
)

def request(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = method.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body)
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  [res.code, res.body]
end

def get(path)
  JSON.parse(request(Net::HTTP::Get, path)[1])
end

ver = get("/v1/apps/#{APP_ID}/appStoreVersions?filter[versionString]=#{version}")['data'][0]
abort "version #{version} not found" unless ver

locs = get("/v1/appStoreVersions/#{ver['id']}/appStoreVersionLocalizations")['data']
locs.each do |loc|
  sets = get("/v1/appStoreVersionLocalizations/#{loc['id']}/appScreenshotSets")['data']
  sets.each do |set|
    shots = get("/v1/appScreenshotSets/#{set['id']}/appScreenshots")['data']
    ordered = shots.sort_by { |s| s['attributes']['fileName'] }
    body = { data: ordered.map { |s| { type: 'appScreenshots', id: s['id'] } } }
    code, = request(Net::HTTP::Patch, "/v1/appScreenshotSets/#{set['id']}/relationships/appScreenshots", body)
    puts "#{loc['attributes']['locale']}: HTTP #{code} #{ordered.map { |s| s['attributes']['fileName'] }}"
  end
end
