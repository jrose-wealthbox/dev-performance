# DevPerf GitHub Activity CLI Implementation Plan

> Historical plan for the initial no-cache implementation. The daily cache extension is documented in `docs/superpowers/specs/2026-09-22-devperf-github-activity-design.md` and `README.md` and supersedes this plan's original no-cache constraint.

> **For agentic workers:** Implement this plan task by task in the current session. Keep the implementation dependency-free and keep fetched activity in memory.

**Goal:** Build a Ruby CLI that collects one repository's GitHub activity for a date range and reports per-metric peer rankings and percentiles.

**Architecture:** `bin/devperf` validates `key=value` arguments. `GitHubClient` wraps read-only `gh api`; `Collector` turns paged REST/GraphQL responses into normalized activity records; `Metrics` calculates the cohort and rankings; `Report` formats the terminal output.

**Tech Stack:** Ruby standard library, GitHub CLI (`gh`), GitHub REST and GraphQL APIs.

Automated tests are omitted in this first pass per the user's preference; rely on Ruby syntax checks and short CLI/data smoke checks instead.

**Spec:** `docs/superpowers/specs/2026-09-22-devperf-github-activity-design.md`

## Global Constraints

- Accept `login`, `repo=owner/name`, and either `days=N` or inclusive `from=YYYY-MM-DD to=YYYY-MM-DD`.
- Use fresh read-only GitHub data and do not create cache or export files.
- Exclude accounts with `type=Bot`, `[bot]` logins, and Dependabot/Renovate identities.
- Report commits, additions, deletions, submitted reviews, comments on own PRs, and comments on others' PRs.
- Rank every metric independently; do not calculate a combined score.
- Use only Ruby standard-library dependencies and the installed `gh` command.

## Review Focus

- Invalid or conflicting date arguments must fail before any API call.
- API list pagination must flatten every page exactly once.
- A review without `submitted_at` is pending and must not count.
- Comment ownership must compare the target PR author's login to the commenter's login.
- Equal metric values must share rank and percentile calculations must apply the documented tie rule.

### Task 1: CLI argument parsing and GitHub CLI client

**Files:**
- Create: `bin/devperf`
- Create: `lib/devperf/github_client.rb`

**Interfaces:**
- `DevPerf::GitHubClient#list(endpoint, params = {})` returns a flat array of decoded JSON items from all pages.
- `DevPerf::GitHubClient#get(endpoint, params = {})` returns one decoded JSON value.
- `DevPerf::GitHubClient#graphql(query, variables = {})` returns the decoded `data` object.
- `DevPerf.parse_arguments(argv, today: Time.now.utc.to_date)` returns a hash containing `:login`, `:repo`, `:from`, and `:to` as strings/Date values.

- [x] Parse only known `key=value` options, validate GitHub login and `owner/name`, parse positive `days` or both ISO dates, reject mixed/inverted ranges, and print help for `--help`.
- [x] Invoke `gh api` with an argument array through `Open3.capture3`; never interpolate arguments into a shell command.
- [x] For REST list calls, pass `--paginate --slurp -F per_page=100`, parse the returned page array, and flatten one level.
- [x] For single GET and GraphQL calls, decode JSON and raise an error that names the endpoint and includes `gh` stderr on failure.
- [x] Run `ruby -c` against the two Ruby files and `bin/devperf --help`.

### Task 2: GitHub activity collector

**Files:**
- Create: `lib/devperf/collector.rb`

**Interfaces:**
- `DevPerf::Collector.new(client).collect(repo:, from:, to:)` returns a hash with `:commits`, `:reviews`, `:comments`, and `:contributors` arrays.
- A commit record contains `:login`, `:type`, `:date`, `:additions`, and `:deletions`.
- A review record contains `:login`, `:pr_owner`, and `:date`.
- A comment record contains `:login`, `:pr_owner`, `:date`, and `:kind` (`:conversation` or `:inline`).
- A contributor record contains `:login`, `:type`, and an observation date used for range filtering.

- [x] Page commits with `since`, `until`, and 100 items per page; locally filter by the committer timestamp.
- [x] Query commit line stats through GraphQL aliases in batches of 50 SHAs; when GraphQL fails or omits a SHA, fetch that commit's REST detail for stats.
- [x] Request pull request pages explicitly in `state=all`, `sort=updated`, `direction=desc`; stop once `updated_at` is earlier than `from` and retain candidates updated on/after `from` so event timestamps can be filtered through `to`.
- [x] For each candidate PR, page its reviews, issue comments, and inline review comments; retain events whose submission/creation date is inclusively within `from..to`.
- [x] Normalize missing user objects safely and preserve account `type` for the metrics layer's bot exclusion.
- [x] Run `ruby -c lib/devperf/collector.rb`.

### Task 3: Cohort aggregation, ranking, and terminal report

**Files:**
- Create: `lib/devperf/metrics.rb`
- Create: `lib/devperf/report.rb`
- Modify: `bin/devperf`

**Interfaces:**
- `DevPerf::Metrics.new(activity, login).rows` returns one row per cohort login with metric values and per-metric rank/percentile metadata.
- Metric keys are `:commits`, `:additions`, `:deletions`, `:reviews`, `:own_pr_comments`, and `:other_pr_comments`.
- `DevPerf::Report.render(rows, login:, repo:, from:, to:)` returns a string containing the summary and full cohort matrix.

- [x] Build cohort membership from human committers, PR authors opening or merging a PR in range, submitted review authors, comment authors, and the supplied login.
- [x] Initialize zeroes for every metric for every cohort login; reject `type=Bot`, `\[bot\]` suffixes, and known Dependabot/Renovate logins case-insensitively.
- [x] Combine conversation and inline comment records, splitting own versus others by target PR author login.
- [x] Compute descending competition rank as `1 + count(value > person's value)` and percentile as `(count(value < person's value) + count(value == person's value) / 2.0) / cohort_size * 100`.
- [x] Render each of the six metrics with the requested user's value, rank, percentile, cohort size, peer median excluding that user, and cohort maximum; then render the cohort metric matrix.
- [x] Run `ruby -c` against both new files and the updated entry point.

### Task 4: Documentation and user-facing smoke checks

**Files:**
- Create: `README.md`

- [x] Document `gh` and Ruby prerequisites, read-only repository permissions, both date-range forms, metric definitions, and the default-branch/identity limitations.
- [x] Show `bin/devperf login=<github-login> repo=<owner/name> days=30` and a 90-day example.
- [x] Run `bin/devperf --help`, a valid parser-only invocation check, and invalid-range checks; confirm invalid arguments exit before `gh` is invoked.
- [x] Inspect whitespace and the final worktree files; do not create tests, cache files, CSVs, or commits.
