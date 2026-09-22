require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../lib/devperf/github_client"

class GitHubClientTest < Minitest::Test
  def test_parameterized_api_lists_explicitly_use_get
    Dir.mktmpdir("devperf-gh") do |directory|
      arguments_path = File.join(directory, "arguments.json")
      gh_path = File.join(directory, "gh")
      File.write(gh_path, <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        File.write(ENV.fetch("DEVPERF_TEST_ARGS"), JSON.generate(ARGV))
        puts "[]"
      RUBY
      File.chmod(0o755, gh_path)

      previous_path = ENV["PATH"]
      previous_arguments_path = ENV["DEVPERF_TEST_ARGS"]
      begin
        ENV["PATH"] = "#{directory}:#{previous_path}"
        ENV["DEVPERF_TEST_ARGS"] = arguments_path

        DevPerf::GitHubClient.new.list("repos/example/project/commits", "since" => "2026-01-01T00:00:00Z")

        arguments = JSON.parse(File.read(arguments_path))
        method_index = arguments.index("--method")
        assert method_index, "expected gh api to specify the HTTP method explicitly"
        assert_equal "GET", arguments[method_index + 1]
      ensure
        ENV["PATH"] = previous_path
        ENV["DEVPERF_TEST_ARGS"] = previous_arguments_path
      end
    end
  end
end
