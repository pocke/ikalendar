require 'sinatra'
require 'icalendar'
require 'json'
require 'net/http'
require 'date'

class CacheStore
  Expire = 60 * 60 # 1 hour
  None = Object.new

  def initialize
    @cache = None
    @cached_time = nil
  end

  def fetch(&block)
    return @cache if cache_available?
    block.call.tap do |v|
      @cache = v
      @cached_time = Time.now.to_i
    end
  end

  private

  def cache_available?
    @cache != None && !expired?
  end

  def expired?
    @cached_time + Expire > Time.now.to_i
  end
end


class Client
  API_URL = 'https://spla2.yuu26.com/schedule'

  def initialize
    @store = CacheStore.new
  end

  def fetch
    @store.fetch do
      JSON.parse(Net::HTTP.get(URI.parse(API_URL)), symbolize_names: true)
    end
  end
end

C = Client.new

get '/ical/all.ics' do
  cal = Icalendar::Calendar.new
  schedule = C.fetch[:result]
  schedule[:regular].each do |regular|
    gachi = schedule[:gachi].find {|g| g[:start_t] == regular[:start_t]}
    league = schedule[:league].find {|l| l[:start_t] == regular[:start_t]}

    cal.event do |e|
      e.dtstart = DateTime.iso8601(regular[:start_utc])
      e.dtend = DateTime.iso8601(regular[:end_utc])
      e.summary = "#{short_rule(regular)} / #{short_rule(gachi)} / #{short_rule(league)}"
      e.description = <<~DESC
        #{regular[:rule]}
        * #{regular[:maps_ex][0][:name]}
        * #{regular[:maps_ex][1][:name]}

        #{gachi[:rule]}
        * #{gachi[:maps_ex][0][:name]}
        * #{gachi[:maps_ex][1][:name]}

        #{league[:rule]}
        * #{league[:maps_ex][0][:name]}
        * #{league[:maps_ex][1][:name]}
      DESC
    end
  end

  cal.publish
  response.headers['Content-Type'] = 'text/calendar; charset=UTF-8'
  cal.to_ical
end

def short_rule(s)
  s[:rule].sub('バトル', '').sub('ガチ', '')
end
