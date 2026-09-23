# DevPerf GitHub Activity CLI Design

## Goal

Build a small Ruby command-line tool that compares the user's recent activity in one GitHub repository with every human account that contributed to that repository during the same date range. The numbers are personal diagnostic signals, not a standalone measure of engineering impact.

## Version 1 command

```sh
bin/devperf login=jrose-wealthbox repo=starburstlabs/crm-web days=90
bin/devperf login=jrose-wealthbox repo=starburstlabs/crm-web from=2026-06-25 to=2026-09-22
```

The command accepts `login`, `repo=owner/name`, and exactly one range form: `days=N` or both `from=YYYY-MM-DD` and `to=YYYY-MM-DD`. `days=N` means exactly N UTC calendar dates, including today. Explicit `from` and `to` dates are inclusive. Invalid, incomplete, or conflicting arguments fail with a concise usage message.

## Data collection

- Use the installed and authenticated `gh` CLI as the only authentication mechanism. Make read-only GitHub REST requests with `gh api`.
- List commits on the repository's default branch within the requested date interval. Attribute each commit by its linked GitHub committer login and use the committer timestamp. Collect additions and deletions from GitHub commit stats, requesting stats in GraphQL batches with a REST per-commit fallback.
- List all-state pull requests sorted by `updated_at` descending. Stop paging when entries are older than the window start; include later-updated PRs as candidates so explicit historical windows can still count events that occurred before their later update. Fetch reviews, PR conversation comments, and inline review comments for each candidate PR, then filter events by `submitted_at` or `created_at` in the inclusive range.
- Count a review when GitHub supplies `submitted_at`; pending reviews are not submissions. Count conversation and inline comments separately during collection, then combine them for the two requested comment metrics.
- Classify a comment as on the commenter's own PR when the PR author login equals the commenter's login; otherwise classify it as on another person's PR.

## Cache behavior

- Cache normalized activity as one JSON file per repository and UTC date at `~/.cache/devperf/v1/<owner>/<repo>/<YYYY-MM-DD>.json`. The `v1` directory isolates this cache format from future versions.
- For requested dates before today, load cache entries first and fetch only missing dates. Fetch missing contiguous ranges in chunks of at most 30 days; write a chunk's daily entries only after its collection completes successfully.
- Always fetch today's activity fresh and never read or write a cache entry for today. Also avoid caching future dates, so an empty future result cannot become stale when the date arrives.
- Cache only the normalized records needed for aggregation; do not persist credentials, raw response pages, or comment bodies.
- If a later chunk fails, earlier completed chunks remain available to the next run. A cold long-range request may still hit API limits: pull-request discovery includes later-updated PRs that may hold events from the selected dates, so chunks may have overlapping PR candidates.

## Cohort, metrics, and ranking

The cohort is the union of human GitHub logins observed as committers, PR authors opening or merging a PR in the range, review authors, or comment authors in the range, plus the requested login even if they have no activity. GitHub accounts with `type=Bot`, logins ending in `[bot]`, and the standard `dependabot`/`renovate` identities are excluded. Commits without a linked GitHub login are not attributed to a person.

For every cohort member, report:

1. Commits
2. Lines added
3. Lines deleted
4. Submitted PR reviews
5. Comments on their own PRs (conversation plus inline review comments)
6. Comments on other people's PRs (conversation plus inline review comments)

For each metric, higher values rank first. Show the user's value, competition rank (`1 + number of people with a higher value`), percentile, cohort size, peer median, and highest value. The peer median excludes the requested login; the maximum includes the whole cohort. Percentile uses the mid-rank tie rule: `(count_below + count_equal / 2) / cohort_size * 100`. Also print the per-person metric matrix so the comparison is inspectable. There is no combined score.

## Architecture

- `bin/devperf`: executable entry point and `key=value` argument validation.
- `lib/devperf/github_client.rb`: safe `gh api` subprocess calls, JSON decoding, pagination, and GraphQL requests.
- `lib/devperf/collector.rb`: GitHub endpoint selection, date filtering, commit-stat batching/fallback, and normalized in-memory activity records.
- `lib/devperf/activity_cache.rb` and `lib/devperf/cached_collector.rb`: daily JSON storage, cache lookup, missing-range fetches, and merging cached/fresh activity.
- `lib/devperf/metrics.rb`: pure cohort aggregation, bot exclusion, per-metric ranks, percentiles, and median calculations.
- `lib/devperf/report.rb`: human-readable terminal report.
- `README.md`: setup, permissions, invocation examples, metric definitions, and limitations.

Only Ruby standard-library code and the existing `gh` executable are required. GitHub access remains read-only; the only persistent output is the local daily JSON cache.

## Errors and limitations

- Missing `gh`, unauthenticated `gh`, API permission errors, inaccessible repositories, and malformed GitHub responses stop the run with a useful message.
- Commit coverage follows the default branch's commit list; unmerged branch-only commits are not included.
- GitHub activity counts show volume, not review quality, impact, complexity, or all work done outside GitHub. Percentiles are descriptive for the selected repository and time window.
- GitHub may not attach a user account to every commit; those records cannot be reliably assigned and are omitted from per-person counts.
- Recent PR activity is discovered through PR `updated_at`; the collector fetches full activity for candidate PRs and filters each event by its own timestamp. Large repositories or old start dates can require many API calls.

## Alternatives considered

- **Ruby plus `gh api` (selected):** matches the requested runtime, uses the user's existing authentication, and avoids dependency installation. A small daily JSON cache handles repeat historical queries without a database.
- **Ruby plus daily JSON cache (selected):** avoids a database dependency and reuses completed dates across weekly runs; SQLite would add unnecessary setup for this single-user script.
- **Adopt `tre-systems/github-org-metrics`:** it already covers broad organization metrics in Python and is MIT-licensed. It remains a useful reference, but the requested Ruby command and own-versus-other PR comment rankings need custom behavior. The local checkout was inspected for API batching and PR collection patterns; no code is copied.

## First-pass verification

Use Ruby syntax validation and CLI help/argument smoke checks. Do not make live GitHub calls as part of routine verification; the user can run the read-only command against their authenticated account.
