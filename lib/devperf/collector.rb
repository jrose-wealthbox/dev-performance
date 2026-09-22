require "date"
require "time"

module DevPerf
  class Collector
    COMMIT_STATS_BATCH_SIZE = 50
    PAGE_SIZE = 100

    def initialize(client)
      @client = client
    end

    def collect(repo:, from:, to:)
      commits = collect_commits(repo, from, to)
      pulls = collect_pull_requests(repo, from)
      reviews = []
      comments = []
      contributors = []

      pulls.each do |pull|
        author = account(pull["user"])
        author_activity_date = [pull["created_at"], pull["merged_at"]].map { |value| github_date(value) }
          .find { |date| in_range?(date, from, to) }
        if author && author_activity_date
          contributors << author.merge(date: author_activity_date)
        end

        number = pull["number"]
        owner_login = author && author[:login]
        collect_reviews(repo, number, owner_login, from, to, reviews, contributors)
        collect_comments(repo, number, owner_login, :conversation, "issues", from, to, comments, contributors)
        collect_comments(repo, number, owner_login, :inline, "pulls", from, to, comments, contributors)
      end

      { commits: commits, reviews: reviews, comments: comments, contributors: contributors }
    end

    private

    def collect_commits(repo, from, to)
      entries = @client.list("repos/#{repo}/commits", "since" => timestamp(from, "00:00:00"), "until" => timestamp(to + 1, "00:00:00"))
      entries = entries.select do |entry|
        date = github_date(entry.dig("commit", "committer", "date"))
        in_range?(date, from, to)
      end

      attributable = entries.map do |entry|
        user = account(entry["committer"])
        sha = entry["sha"]
        next unless user && sha

        { entry: entry, user: user, sha: sha, date: github_date(entry.dig("commit", "committer", "date")) }
      end.compact

      stats = commit_stats(repo, attributable.map { |item| item[:sha] })
      attributable.map do |item|
        commit_stats = stats[item[:sha]] || {}
        user = item[:user]
        { login: user[:login], type: user[:type], date: item[:date],
          additions: integer(commit_stats["additions"]), deletions: integer(commit_stats["deletions"]) }
      end
    end

    def commit_stats(repo, shas)
      stats = {}
      shas.each_slice(COMMIT_STATS_BATCH_SIZE) do |batch|
        begin
          stats.merge!(graphql_commit_stats(repo, batch))
        rescue Error => error
          warn "devperf: GraphQL line stats unavailable; using REST for this batch (#{error.message})"
        end

        (batch - stats.keys).each do |sha|
          detail = @client.get("repos/#{repo}/commits/#{sha}")
          stats[sha] = detail["stats"] if detail.is_a?(Hash) && detail["stats"].is_a?(Hash)
        end
      end
      stats
    end

    def graphql_commit_stats(repo, shas)
      owner, name = repo.split("/", 2)
      fields = shas.each_with_index.map do |sha, index|
        "c#{index}: object(oid: \"#{sha}\") { ... on Commit { additions deletions } }"
      end.join("\n")
      query = "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { #{fields} } }"
      repository = @client.graphql(query, "owner" => owner, "name" => name)["repository"]
      return {} unless repository.is_a?(Hash)

      shas.each_with_index.each_with_object({}) do |(sha, index), result|
        item = repository["c#{index}"]
        next unless item.is_a?(Hash)

        result[sha] = { "additions" => item["additions"], "deletions" => item["deletions"] }
      end
    end

    def collect_pull_requests(repo, from)
      pulls = []
      page = 1
      loop do
        batch = @client.get("repos/#{repo}/pulls", "state" => "all", "sort" => "updated",
                            "direction" => "desc", "per_page" => PAGE_SIZE, "page" => page)
        raise Error, "Unexpected pull request list response for #{repo}" unless batch.is_a?(Array)
        break if batch.empty?

        cutoff_reached = false
        batch.each do |pull|
          updated = github_date(pull["updated_at"])
          if updated && updated < from
            cutoff_reached = true
            break
          end
          pulls << pull
        end
        break if cutoff_reached || batch.length < PAGE_SIZE

        page += 1
      end
      pulls
    end

    def collect_reviews(repo, number, owner_login, from, to, reviews, contributors)
      @client.list("repos/#{repo}/pulls/#{number}/reviews").each do |review|
        date = github_date(review["submitted_at"])
        next unless in_range?(date, from, to)

        user = account(review["user"])
        next unless user

        reviews << user.merge(pr_owner: owner_login, date: date)
        contributors << user.merge(date: date)
      end
    end

    def collect_comments(repo, number, owner_login, kind, endpoint, from, to, comments, contributors)
      @client.list("repos/#{repo}/#{endpoint}/#{number}/comments").each do |comment|
        date = github_date(comment["created_at"])
        next unless in_range?(date, from, to)

        user = account(comment["user"])
        next unless user

        comments << user.merge(pr_owner: owner_login, date: date, kind: kind)
        contributors << user.merge(date: date)
      end
    end

    def account(user)
      return unless user.is_a?(Hash) && user["login"].is_a?(String)

      { login: user["login"], type: user["type"] }
    end

    def github_date(value)
      return unless value.is_a?(String)

      Time.iso8601(value).utc.to_date
    rescue ArgumentError
      nil
    end

    def in_range?(date, from, to)
      date && date >= from && date <= to
    end

    def timestamp(date, time)
      "#{date.iso8601}T#{time}Z"
    end

    def integer(value)
      Integer(value || 0)
    rescue ArgumentError, TypeError
      0
    end
  end
end
