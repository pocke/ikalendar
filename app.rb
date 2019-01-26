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

DEFAULT_TITLE_FORMAT = '%{regular:short_rule} / %{gachi:short_rule} / %{league:short_rule}'
DEFAULT_DESCRIPTION_FORMAT = <<~DESC
  %{regular:rule}
  * %{regular:map1}
  * %{regular:map2}

  %{gachi:rule}
  * %{gachi:map1}
  * %{gachi:map2}

  %{league:rule}
  * %{league:map1}
  * %{league:map2}
DESC

get '/ical/all.ics' do
  title_format = params[:title_format] || DEFAULT_TITLE_FORMAT
  desc_format = params[:description_format] || DEFAULT_DESCRIPTION_FORMAT

  cal = Icalendar::Calendar.new
  schedule = C.fetch[:result]
  schedule[:regular].each do |regular|
    gachi = schedule[:gachi].find {|g| g[:start_t] == regular[:start_t]}
    league = schedule[:league].find {|l| l[:start_t] == regular[:start_t]}

    cal.event do |e|
      e.dtstart = DateTime.iso8601(regular[:start_utc])
      e.dtend = DateTime.iso8601(regular[:end_utc])
      e.summary = apply_format(title_format, {regular: regular, gachi: gachi, league: league})
      e.description = apply_format(desc_format, {regular: regular, gachi: gachi, league: league})
    end
  end

  cal.publish
  response.headers['Content-Type'] = 'text/calendar; charset=UTF-8'
  cal.to_ical
end

def short_rule(s)
  s[:rule].sub('バトル', '').sub('ガチ', '')
end

def apply_format(fmt, events)
  res = fmt.dup
  %i[regular gachi league].each do |mode|
    res.gsub!("%{#{mode}:short_rule}", short_rule(events[mode]))
    res.gsub!("%{#{mode}:rule}", events[mode][:rule_ex][:name])
    res.gsub!("%{#{mode}:map1}", events[mode][:maps_ex][0][:name])
    res.gsub!("%{#{mode}:map2}", events[mode][:maps_ex][1][:name])
  end
  res
end
