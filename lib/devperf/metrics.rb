module DevPerf
  class Metrics
    METRICS = {
      commits: "Commits",
      additions: "Lines added",
      deletions: "Lines deleted",
      reviews: "PR reviews submitted",
      own_pr_comments: "Comments on own PRs",
      other_pr_comments: "Comments on others' PRs"
    }.freeze

    def initialize(activity, login)
      @activity = activity
      @login = login
    end

    def rows
      people = {}
      excluded = bot_logins

      Array(@activity[:contributors]).each do |person|
        add_person(people, person, excluded) if person[:date]
      end
      Array(@activity[:commits]).each do |commit|
        person = add_person(people, commit, excluded)
        next unless person

        person[:commits] += 1
        person[:additions] += commit[:additions].to_i
        person[:deletions] += commit[:deletions].to_i
      end
      Array(@activity[:reviews]).each do |review|
        person = add_person(people, review, excluded)
        person[:reviews] += 1 if person
      end
      Array(@activity[:comments]).each do |comment|
        person = add_person(people, comment, excluded)
        next unless person && comment[:pr_owner]

        metric = comment[:login].casecmp(comment[:pr_owner]).zero? ? :own_pr_comments : :other_pr_comments
        person[metric] += 1
      end

      add_person(people, { login: @login, type: "User" }, excluded)
      people.values.each { |person| person[:rankings] = {} }

      METRICS.each_key do |metric|
        values = people.values.map { |person| person[metric] }
        people.values.each do |person|
          below = values.count { |value| value < person[metric] }
          equal = values.count { |value| value == person[metric] }
          higher = values.count { |value| value > person[metric] }
          peers = people.values.reject { |peer| peer[:login].casecmp(@login).zero? }

          person[:rankings][metric] = {
            rank: higher + 1,
            percentile: (below + equal / 2.0) / values.length * 100,
            cohort_size: values.length,
            peer_median: median(peers.map { |peer| peer[metric] }),
            highest: values.max || 0
          }
        end
      end

      people.values.sort_by { |person| person[:login].downcase }
    end

    private

    def bot_logins
      records = Array(@activity[:contributors]) + Array(@activity[:commits]) +
        Array(@activity[:reviews]) + Array(@activity[:comments])
      records.each_with_object({}) do |record, result|
        next unless record[:login]
        next unless bot?(record[:login], record[:type])

        result[record[:login].downcase] = true
      end
    end

    def add_person(people, record, excluded)
      login = record[:login]
      return unless login.is_a?(String) && !login.empty?

      key = login.downcase
      return if excluded[key] || bot?(login, record[:type])

      people[key] ||= {
        login: login,
        commits: 0,
        additions: 0,
        deletions: 0,
        reviews: 0,
        own_pr_comments: 0,
        other_pr_comments: 0
      }
    end

    def bot?(login, type)
      type.to_s.casecmp("bot").zero? || login.match?(/\[bot\]\z/i) ||
        login.match?(/\A(?:dependabot(?:-preview)?|renovate(?:-bot)?)\z/i)
    end

    def median(numbers)
      values = numbers.sort
      return if values.empty?

      middle = values.length / 2
      return values[middle] if values.length.odd?

      (values[middle - 1] + values[middle]) / 2.0
    end
  end
end
