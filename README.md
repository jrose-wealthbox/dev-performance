# DevPerf

A small local Ruby CLI for comparing GitHub activity in one repository over a selected date range. It uses activity counts as descriptive signals; commits, lines changed, reviews, and comments do not measure impact or review quality on their own.

## Requirements

- Ruby 2.6 or newer
- GitHub CLI (`gh`) installed and authenticated
- Read access to the repository's contents and pull requests (for a private repository)
- Write access under the local cache directory (`~/.cache/devperf`)

Check GitHub CLI authentication with:

```sh
gh auth status
```

The script makes read-only API calls through `gh api`. It does not store a token or use a separate GitHub SDK.

## Usage

Run the executable from the repository root:

```sh
bin/devperf login=jrose-wealthbox repo=starburstlabs/crm-web days=30
bin/devperf login=jrose-wealthbox repo=starburstlabs/crm-web days=90
```

Or provide exact inclusive UTC dates:

```sh
bin/devperf login=jrose-wealthbox repo=starburstlabs/crm-web from=2026-06-25 to=2026-09-22
```

`days=N` covers exactly N UTC calendar dates, including today. `from` and `to` must be supplied together and cannot be combined with `days`.

## Local cache

Completed historical activity is cached as one JSON file per UTC date:

```text
~/.cache/devperf/v1/<owner>/<repo>/<YYYY-MM-DD>.json
```

The files contain only normalized account/date/count records needed for the report—not GitHub credentials, raw API responses, or comment text. Cached days are reused across overlapping date ranges. Today's partial results and future dates are always fetched fresh and are never cached. Missing dates are fetched in contiguous chunks of at most 30 days; each successfully completed chunk is cached before the next starts.

A cold request can still hit GitHub's API limit. In particular, PR activity discovery includes PRs updated after the requested dates so that older reviews and comments on those PRs are not missed; the current collector may therefore revisit PRs across date chunks. Completed chunks remain cached if a later chunk fails, so rerunning can reuse that work. To force a historical refresh, remove the corresponding date files under `~/.cache/devperf/v1` before running again.

## What it reports

For each human contributor observed in the selected range, DevPerf reports:

- Commits on the repository's default branch, attributed to the linked GitHub committer account
- Lines added and deleted, using GitHub's commit statistics
- Submitted pull request reviews (pending reviews are not counted)
- Comments on the user's own pull requests
- Comments on other contributors' pull requests

The two comment counts include both PR conversation comments and inline review comments. For every metric, the summary shows your value, competition rank, percentile, cohort size, the other contributors' median, and the highest cohort value. Ties share a competition rank. Percentile uses the midrank rule: contributors below your value plus half of those tied, divided by cohort size. No combined score is calculated. Bot accounts identified by GitHub, `[bot]` logins, Dependabot, and Renovate are excluded.

## Progress output

During collection, DevPerf prints and flushes status messages to stdout. After the total is known, commit line-stat and pull-request activity progress is reported about every 10% for smaller groups and every 100 items for larger groups. For example, a run with 2,700 attributable commits prints 27 line-stat progress messages. The final report follows the collection status.

## Limitations

- Commits come from the repository's default-branch commit list; commits that exist only on unmerged branches are not counted.
- Commits without a linked GitHub committer login cannot be assigned to a person and are omitted from per-person metrics.
- GitHub activity counts do not capture work outside GitHub, complexity, impact, or review quality.
- Pull request details require several API requests per candidate PR. Large repositories and long historical ranges may take time or encounter GitHub API limits.
- Role-based cohorts and multiple repositories are not implemented yet.

For additional GitHub metric ideas, the MIT-licensed [`github-org-metrics`](https://github.com/tre-systems/github-org-metrics) project informed the API collection approach. No code from that project is copied here.
