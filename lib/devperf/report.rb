module DevPerf
  class Report
    def self.render(rows, login:, repo:, from:, to:)
      me = rows.find { |row| row[:login].casecmp(login).zero? }
      return "No human contributors found for this date range.\n" unless me

      lines = []
      lines << "DevPerf: #{repo}"
      lines << "Window: #{from.iso8601} through #{to.iso8601} (UTC, inclusive)"
      lines << "Cohort: #{rows.length} human contributors, including #{me[:login]}"
      lines << ""
      lines << "Your per-metric ranking (higher values rank first)"

      summary_rows = Metrics::METRICS.map do |key, label|
        ranking = me[:rankings][key]
        [label, number(me[key]), "#{ranking[:rank]}/#{ranking[:cohort_size]}",
         format("%.1f%%", ranking[:percentile]), number(ranking[:peer_median]), number(ranking[:highest])]
      end
      lines.concat(table(["Metric", "You", "Rank", "Percentile", "Peer median", "Highest"], summary_rows))
      lines << ""
      lines << "Contributor activity"

      matrix = rows.map do |row|
        [row[:login], number(row[:commits]), number(row[:additions]), number(row[:deletions]),
         number(row[:reviews]), number(row[:own_pr_comments]), number(row[:other_pr_comments])]
      end
      lines.concat(table(["GitHub login", "Commits", "Added", "Deleted", "Reviews", "Own PR comments", "Other PR comments"], matrix))
      lines << ""
      lines << "Comments combine PR conversation comments and inline review comments."
      lines << ""
      lines.join("\n")
    end

    def self.table(headers, rows)
      widths = headers.each_index.map do |index|
        ([headers[index].length] + rows.map { |row| row[index].to_s.length }).max
      end
      formatted = [headers, *rows].map do |row|
        row.each_with_index.map { |value, index| value.to_s.ljust(widths[index]) }.join("  ").rstrip
      end
      formatted
    end

    def self.number(value)
      return "—" if value.nil?

      value.is_a?(Float) && value % 1 != 0 ? format("%.1f", value) : value.to_i.to_s
    end

    private_class_method :table, :number
  end
end
