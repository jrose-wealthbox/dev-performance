# Repository instructions

## Project scope

- Keep DevPerf a small local Ruby CLI. Prefer Ruby's standard library and the installed GitHub CLI (`gh`) over adding dependencies or infrastructure.
- GitHub collection is read-only. Do not store credentials or add writes to the GitHub API.
- Commits, lines changed, reviews, and comments are descriptive signals, not measures of impact or quality. Preserve that framing and do not introduce a combined score without an explicit request.
- Date ranges are inclusive UTC calendar dates; `days=N` includes today and the preceding `N - 1` dates.
- Multiple repositories and role-based cohorts are future work. Do not expand the current single-repository, all-human-contributors behavior unless requested.

## Development and verification

- The CLI entry point is `bin/devperf`; implementation lives in `lib/devperf/`.
- Run the test suite from the repository root with:

  ```sh
  ruby -Ilib -e 'Dir["test/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
  ```

- Keep tests offline by using a fake GitHub client rather than making live API calls.
- Parameterized REST reads through `gh api` must specify `--method GET`; GraphQL requests use POST.
- Keep progress/status output on stdout and errors on stderr.
- Stage only files in scope when committing; preserve unrelated worktree changes.
