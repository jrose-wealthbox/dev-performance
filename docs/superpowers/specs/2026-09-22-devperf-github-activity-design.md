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
- `lib/devperf/metrics.rb`: pure cohort aggregation, bot exclusion, per-metric ranks, percentiles, and median calculations.
- `lib/devperf/report.rb`: human-readable terminal report.
- `README.md`: setup, permissions, invocation examples, metric definitions, and limitations.

Only Ruby standard-library code and the existing `gh` executable are required. The tool fetches fresh data every run, keeps it in memory, and writes no cache or export files.

## Errors and limitations

- Missing `gh`, unauthenticated `gh`, API permission errors, inaccessible repositories, and malformed GitHub responses stop the run with a useful message.
- Commit coverage follows the default branch's commit list; unmerged branch-only commits are not included.
- GitHub activity counts show volume, not review quality, impact, complexity, or all work done outside GitHub. Percentiles are descriptive for the selected repository and time window.
- GitHub may not attach a user account to every commit; those records cannot be reliably assigned and are omitted from per-person counts.
- Recent PR activity is discovered through PR `updated_at`; the collector fetches full activity for candidate PRs and filters each event by its own timestamp. Large repositories or old start dates can require many API calls.

## Alternatives considered

- **Ruby plus `gh api` (selected):** matches the requested runtime, uses the user's existing authentication, and avoids dependency installation and persistent storage.
- **Ruby plus SQLite or raw JSON cache:** useful for offline re-analysis and repeated historical queries, but unnecessary for weekly fresh runs and adds state to manage.
- **Adopt `tre-systems/github-org-metrics`:** it already covers broad organization metrics in Python and is MIT-licensed. It remains a useful reference, but the requested Ruby command and own-versus-other PR comment rankings need custom behavior. The local checkout was inspected for API batching and PR collection patterns; no code is copied.

## First-pass verification

Use Ruby syntax validation and CLI help/argument smoke checks. Do not make live GitHub calls as part of routine verification; the user can run the read-only command against their authenticated account.
