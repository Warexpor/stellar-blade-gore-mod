---
name: prepare-publish
description: Prepare a Stellar Blade Gore Mod release, deliver the verified ZIP to Downloads, and open the review PR from dev to main.
---

# Prepare a Stellar Blade Gore Mod release

A plain `$prepare-publish` invocation requests the full workflow below, including delivery to Downloads, a push to `origin/dev`, and a PR to `main`. Explicit local-only, candidate-only, or build-only requests narrow that scope.

1. Prepare the release on `dev`. Follow `AGENTS.md` for versioning, checks, and local installation. Preserve unrelated changes and commit only release work.
2. Build the ZIP in `release/` using `package.sh` through the documented Windows or Linux workflow. Its `--reuse` option is suitable for unchanged paks when their vanilla provenance and contents are verified against the previous release. Check the archive layout, scripts, DLL version, and exclusion of local settings. Copy the verified ZIP to the user's Downloads folder and compare hashes. On Windows use the configured Downloads folder so redirected paths work. Preserve any existing file with different contents.
3. Push the release commit to `origin/dev` and open a GitHub PR with `dev` as the head and `main` as the base. Reuse an existing open PR for that pair and link it in the response. Include checks performed and any remaining in-game validation in the PR. The default workflow ends with an open PR and the ZIP in Downloads. Merging, tagging, and uploading to GitHub Releases or Nexus require a separate request.
