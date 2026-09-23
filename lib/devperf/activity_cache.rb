require "date"
require "fileutils"
require "json"

require_relative "github_client"

module DevPerf
  class ActivityCache
    CACHE_DIRECTORY_VERSION = "v1".freeze
    FORMAT_VERSION = 1
    FIELDS = {
      commits: %i[login type date additions deletions],
      reviews: %i[login pr_owner date],
      comments: %i[login pr_owner date kind],
      contributors: %i[login type date]
    }.freeze

    def initialize(root: File.join(Dir.home, ".cache", "devperf"))
      @root = File.expand_path(root)
    end

    def read(repo:, date:)
      path = path_for(repo, date)
      return unless File.file?(path)

      document = JSON.parse(File.read(path))
      validate_document(document, repo, date, path)
      FIELDS.each_with_object({}) do |(category, fields), activity|
        records = document.fetch("activity").fetch(category.to_s)
        activity[category] = records.map do |record|
          fields.each_with_object({}) do |field, decoded|
            value = record[field.to_s]
            value = Date.iso8601(value) if field == :date
            value = value.to_sym if field == :kind && value
            decoded[field] = value
          end
        end
      end
    rescue JSON::ParserError, Date::Error, KeyError, NoMethodError, TypeError => error
      raise Error, "Could not read DevPerf cache #{path}: #{error.message}"
    end

    def write(repo:, date:, activity:)
      path = path_for(repo, date)
      document = {
        "format_version" => FORMAT_VERSION,
        "repo" => repo,
        "date" => date.iso8601,
        "activity" => FIELDS.each_with_object({}) do |(category, fields), result|
          result[category.to_s] = Array(activity[category]).map do |record|
            fields.each_with_object({}) do |field, encoded|
              value = record[field]
              value = value.iso8601 if field == :date && value
              value = value.to_s if field == :kind && value
              encoded[field.to_s] = value
            end
          end
        end
      }

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(document) + "\n")
    end

    private

    def path_for(repo, date)
      parts = repo.split("/", -1)
      unless parts.length == 2 && parts.all? { |part| part.match?(/\A[a-zA-Z0-9._-]+\z/) } &&
          parts.none? { |part| part == "." || part == ".." }
        raise ArgumentError, "repo must be written as owner/name"
      end

      File.join(@root, CACHE_DIRECTORY_VERSION, parts[0], parts[1], "#{date.iso8601}.json")
    end

    def validate_document(document, repo, date, path)
      valid = document.is_a?(Hash) && document["format_version"] == FORMAT_VERSION &&
        document["repo"] == repo && document["date"] == date.iso8601 &&
        document["activity"].is_a?(Hash) && FIELDS.keys.all? do |category|
          document["activity"][category.to_s].is_a?(Array)
        end
      return if valid

      raise Error, "Unsupported or mismatched DevPerf cache entry: #{path}"
    end
  end
end
