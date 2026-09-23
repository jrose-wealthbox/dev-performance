require "minitest/autorun"

require_relative "../lib/devperf/collector"
require_relative "../lib/devperf/github_client"

class CollectorProgressTest < Minitest::Test
  def test_commit_stats_progress_reports_every_hundred_for_2700_commits
    commits = Array.new(2700) do |index|
      {
        "sha" => "sha-#{index}",
        "committer" => { "login" => "engineer-#{index}", "type" => "User" },
        "commit" => { "committer" => { "date" => "2026-01-15T12:00:00Z" } }
      }
    end

    output, = capture_io do
      DevPerf::Collector.new(ProgressTestGitHubClient.new(commits: commits)).collect(
        repo: "example/project", from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31)
      )
    end

    progress = output.lines.grep(/^Commit line stats: /)
    assert_equal 27, progress.length
    assert_equal "Commit line stats: 100/2700\n", progress.first
    assert_equal "Commit line stats: 2700/2700\n", progress.last
  end

  def test_pull_request_activity_progress_reports_each_item_for_small_cohort
    pulls = Array.new(11) do |index|
      {
        "number" => index + 1,
        "user" => { "login" => "author-#{index}", "type" => "User" },
        "created_at" => "2026-01-15T12:00:00Z",
        "updated_at" => "2026-01-15T12:00:00Z"
      }
    end

    output, = capture_io do
      DevPerf::Collector.new(ProgressTestGitHubClient.new(pulls: pulls)).collect(
        repo: "example/project", from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31)
      )
    end

    progress = output.lines.grep(/^Pull request activity: /)
    assert_equal 11, progress.length
    assert_equal "Pull request activity: 1/11\n", progress.first
    assert_equal "Pull request activity: 11/11\n", progress.last
  end
end

class ProgressTestGitHubClient
  def initialize(commits: [], pulls: [])
    @commits = commits
    @pulls = pulls
  end

  def list(endpoint, _params = {})
    endpoint.end_with?("/commits") ? @commits : []
  end

  def get(endpoint, _params = {})
    endpoint.end_with?("/pulls") ? @pulls : {}
  end

  def graphql(query, _variables = {})
    aliases = query.scan(/c(\d+): object/).flatten
    repository = aliases.each_with_object({}) do |index, result|
      result["c#{index}"] = { "additions" => 1, "deletions" => 0 }
    end
    { "repository" => repository }
  end
end
