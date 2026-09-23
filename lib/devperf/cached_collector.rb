require "date"

module DevPerf
  class CachedCollector
    MAX_FETCH_DAYS = 30
    ACTIVITY_KEYS = %i[commits reviews comments contributors].freeze

    def initialize(collector, cache:, today: Time.now.utc.to_date)
      @collector = collector
      @cache = cache
      @today = today
    end

    def collect(repo:, from:, to:)
      dates = (from..to).to_a
      daily_activity = {}
      missing_dates = []

      dates.each do |date|
        cached = date < @today && @cache.read(repo: repo, date: date)
        if cached
          daily_activity[date] = cached
        else
          missing_dates << date
        end
      end

      ranges = missing_ranges(missing_dates)
      if missing_dates.empty?
        status("Cache: using cached activity for all #{dates.length} days; no GitHub fetch required.")
      else
        status("Cache: using #{daily_activity.length}/#{dates.length} cached days; fetching " \
               "#{missing_dates.length} missing #{pluralize(missing_dates.length, 'day')} " \
               "in #{ranges.length} chunk(s).")
      end

      ranges.each do |start_date, end_date|
        status("Fetching #{repo} activity for #{start_date.iso8601} through #{end_date.iso8601}...")
        fetched = @collector.collect(repo: repo, from: start_date, to: end_date)
        by_date = split_by_date(fetched)

        (start_date..end_date).each do |date|
          day = by_date.fetch(date) { empty_activity }
          @cache.write(repo: repo, date: date, activity: day) if date < @today
          daily_activity[date] = day
        end
        cacheable_days = (start_date..end_date).count { |date| date < @today }
        status("Cached activity for #{cacheable_days} historical #{pluralize(cacheable_days, 'day')}.") if cacheable_days.positive?
      end

      merge_days(dates.map { |date| daily_activity.fetch(date) })
    end

    private

    def missing_ranges(dates)
      chunks = []
      dates.each do |date|
        if chunks.empty? || date != chunks.last.last + 1 || chunks.last.length >= MAX_FETCH_DAYS
          chunks << [date]
        else
          chunks.last << date
        end
      end
      chunks.map { |chunk| [chunk.first, chunk.last] }
    end

    def split_by_date(activity)
      by_date = Hash.new { |hash, date| hash[date] = empty_activity }
      ACTIVITY_KEYS.each do |key|
        Array(activity[key]).each do |record|
          by_date[record[:date]][key] << record
        end
      end
      by_date
    end

    def empty_activity
      ACTIVITY_KEYS.each_with_object({}) { |key, result| result[key] = [] }
    end

    def merge_days(days)
      ACTIVITY_KEYS.each_with_object({}) do |key, activity|
        activity[key] = days.flat_map { |day| day.fetch(key) }
      end
    end

    def pluralize(count, noun)
      count == 1 ? noun : "#{noun}s"
    end

    def status(message)
      $stdout.puts(message)
      $stdout.flush
    end
  end
end
