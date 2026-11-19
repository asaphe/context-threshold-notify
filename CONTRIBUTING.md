# Contributing to context-threshold-notify

Thanks for considering a contribution.

## Developer Certificate of Origin (DCO)

Contributions require a sign-off, not a signed CLA. Add `-s` to your commits:

```sh
git commit -s -m "fix: ..."
```

This adds a `Signed-off-by` trailer certifying you have the right to submit
the change under this project's license (MIT). See
[developercertificate.org](https://developercertificate.org/) for the exact
text you're certifying.

The `DCO` check fails a pull request with a commit whose `Signed-off-by` names neither the commit's author nor its committer email (case-insensitive); merge commits and Dependabot's pull requests are exempt.

## Before opening a PR

```sh
sh tests/run.sh
sh tests/dco.sh
shellcheck -s sh -S warning scripts/*.sh tests/*.sh .github/scripts/*.sh
claude plugin validate .
```

CI runs the tests on macOS and Linux. macOS `/bin/sh` is bash in POSIX mode and Linux
`sh` is usually dash, and they differ (a `VAR=x func` prefix stays set after the function
returns in bash), so a change must pass on both.

## Versioning

`claude plugin update` compares the `version` in `.claude-plugin/plugin.json`, so a change
that does not bump it never reaches installed copies. Bump it in every PR that changes the
plugin (hooks, scripts, options): patch for fixes, minor for new behaviour.

## Changing how context is counted

Claude Code's transcript format can change between releases. A change to the token
count needs a test that reproduces the case, and the PR description should name the
Claude Code version and the transcript line you observed it on.
