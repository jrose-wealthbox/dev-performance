require "date"
require "minitest/autorun"
require "tmpdir"

require_relative "../lib/devperf/github_client"
require_relative "../lib/devperf/activity_cache"
require_relative "../lib/devperf/cached_collector"

class ActivityCacheTest < Minitest::Test
  def test_json_cache_round_trips_records_and_is_scoped_by_repository_and_date
    Dir.mktmpdir("devperf-cache") do |directory|
      cache = DevPerf::ActivityCache.new(root: directory)
      date = Date.new(2026, 1, 3)
      data = activity(
        commits: [{ login: "jrose", type: "User", date: date, additions: 4, deletions: 2 }],
        reviews: [{ login: "alex", pr_owner: "jrose", date: date }],
        comments: [{ login: "alex", pr_owner: "jrose", date: date, kind: :inline }],
        contributors: [{ login: "jrose", type: "User", date: date }]
      )

      cache.write(repo: "acme/one", date: date, activity: data)

      assert File.file?(File.join(directory, "v1", "acme", "one", "2026-01-03.json"))
      assert_equal data, cache.read(repo: "acme/one", date: date)
      assert_nil cache.read(repo: "acme/two", date: date)
      assert_nil cache.read(repo: "acme/one", date: date + 1)
    end
  end

  def test_cached_collector_fetches_only_missing_historical_dates_and_merges_activity
    Dir.mktmpdir("devperf-cache") do |directory|
      cache = DevPerf::ActivityCache.new(root: directory)
      repo = "acme/one"
      first = Date.new(2026, 1, 1)
      second = Date.new(2026, 1, 2)
      third = Date.new(2026, 1, 3)
      cache.write(repo: repo, date: first,
                  activity: activity(commits: [commit("cached", first)]))
      collector = RecordingActivityCollector.new do |_repo, _from, _to|
        activity(commits: [commit("fresh", third)])
      end

      result = DevPerf::CachedCollector.new(collector, cache: cache, today: Date.new(2026, 1, 10))
        .collect(repo: repo, from: first, to: third)

      assert_equal [[second, third]], collector.calls.map { |call| call.values_at(:from, :to) }
      assert_equal %w[cached fresh], result[:commits].map { |record| record[:login] }
      assert_equal activity, cache.read(repo: repo, date: second)
    end
  end

  def test_current_day_ignores_existing_partial_cache_and_is_not_persisted
    Dir.mktmpdir("devperf-cache") do |directory|
      cache = DevPerf::ActivityCache.new(root: directory)
      today = Date.new(2026, 1, 3)
      repo = "acme/one"
      partial = activity(commits: [commit("partial", today)])
      cache.write(repo: repo, date: today, activity: partial)
      collector = RecordingActivityCollector.new do |_repo, _from, _to|
        activity(commits: [commit("fresh", today)])
      end

      result = DevPerf::CachedCollector.new(collector, cache: cache, today: today)
        .collect(repo: repo, from: today, to: today)
      second_result = DevPerf::CachedCollector.new(collector, cache: cache, today: today)
        .collect(repo: "acme/two", from: today, to: today)

      assert_equal [[today, today], [today, today]], collector.calls.map { |call| call.values_at(:from, :to) }
      assert_equal ["fresh"], result[:commits].map { |record| record[:login] }
      assert_equal ["fresh"], second_result[:commits].map { |record| record[:login] }
      assert_equal partial, cache.read(repo: repo, date: today)
      assert_nil cache.read(repo: "acme/two", date: today)
    end
  end

  def test_uncached_history_is_fetched_in_chunks_of_at_most_thirty_days
    Dir.mktmpdir("devperf-cache") do |directory|
      cache = DevPerf::ActivityCache.new(root: directory)
      from = Date.new(2026, 1, 1)
      to = Date.new(2026, 3, 6)
      collector = RecordingActivityCollector.new do |_repo, _from, _to|
        activity
      end

      DevPerf::CachedCollector.new(collector, cache: cache, today: Date.new(2026, 3, 7))
        .collect(repo: "acme/one", from: from, to: to)

      assert_equal [
        [Date.new(2026, 1, 1), Date.new(2026, 1, 30)],
        [Date.new(2026, 1, 31), Date.new(2026, 3, 1)],
        [Date.new(2026, 3, 2), Date.new(2026, 3, 6)]
      ], collector.calls.map { |call| call.values_at(:from, :to) }
      assert_equal activity, cache.read(repo: "acme/one", date: to)
    end
  end

  def test_future_dates_are_fetched_fresh_and_not_cached
    Dir.mktmpdir("devperf-cache") do |directory|
      cache = DevPerf::ActivityCache.new(root: directory)
      today = Date.new(2026, 1, 3)
      future = today + 1
      collector = RecordingActivityCollector.new { |_repo, _from, _to| activity }

      DevPerf::CachedCollector.new(collector, cache: cache, today: today)
        .collect(repo: "acme/one", from: future, to: future)

      assert_equal [[future, future]], collector.calls.map { |call| call.values_at(:from, :to) }
      assert_nil cache.read(repo: "acme/one", date: future)
    end
  end

  private

  def activity(commits: [], reviews: [], comments: [], contributors: [])
    { commits: commits, reviews: reviews, comments: comments, contributors: contributors }
  end

  def commit(login, date)
    { login: login, type: "User", date: date, additions: 1, deletions: 0 }
  end
end

class RecordingActivityCollector
  attr_reader :calls

  def initialize(&response)
    @response = response
    @calls = []
  end

  def collect(repo:, from:, to:)
    @calls << { repo: repo, from: from, to: to }
    @response.call(repo, from, to)
  end
end
