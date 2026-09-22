require "json"
require "open3"

module DevPerf
  class Error < StandardError; end

  class GitHubClient
    def list(endpoint, params = {})
      arguments = ["api", "--paginate", "--slurp", endpoint]
      add_fields(arguments, { "per_page" => 100 }.merge(stringify_keys(params)))

      pages = parse_json(run(arguments, endpoint), endpoint)
      raise Error, "Expected a paginated list from #{endpoint}" unless pages.is_a?(Array)

      pages.flat_map do |page|
        raise Error, "Unexpected page format from #{endpoint}" unless page.is_a?(Array)

        page
      end
    end

    def get(endpoint, params = {})
      arguments = ["api", endpoint]
      add_fields(arguments, stringify_keys(params))
      parse_json(run(arguments, endpoint), endpoint)
    end

    def graphql(query, variables = {})
      arguments = ["api", "graphql", "-f", "query=#{query}"]
      stringify_keys(variables).each do |key, value|
        arguments.concat(["-f", "#{key}=#{value}"])
      end

      response = parse_json(run(arguments, "GraphQL request"), "GraphQL request")
      if response["data"].nil?
        details = Array(response["errors"]).map { |error| error["message"] }.compact.join("; ")
        raise Error, "GitHub GraphQL request returned no data#{": #{details}" unless details.empty?}"
      end

      response["data"]
    end

    private

    def add_fields(arguments, params)
      arguments.concat(["--method", "GET"]) unless params.empty?
      params.each do |key, value|
        arguments.concat(["-F", "#{key}=#{value}"])
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value.to_s }
    end

    def run(arguments, label)
      stdout, stderr, status = Open3.capture3("gh", *arguments)
      return stdout if status.success?

      message = stderr.strip
      message = "gh exited with status #{status.exitstatus}" if message.empty?
      raise Error, "#{label}: #{message}"
    rescue Errno::ENOENT
      raise Error, "GitHub CLI `gh` was not found in PATH"
    end

    def parse_json(output, label)
      JSON.parse(output)
    rescue JSON::ParserError => error
      raise Error, "Could not parse JSON from #{label}: #{error.message}"
    end
  end
end
