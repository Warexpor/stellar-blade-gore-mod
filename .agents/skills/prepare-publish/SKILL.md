---
name: prepare-publish
description: Prepare a Stellar Blade Gore Mod release, deliver the verified ZIP to Downloads, and merge the release PR from dev to main.
---

# Prepare a Stellar Blade Gore Mod release

A plain `$prepare-publish` invocation requests the full workflow below through a merged PR and a verified ZIP in Downloads. Explicit local-only, candidate-only, build-only, or PR-only requests narrow that scope.

1. Prepare the release on `dev`. Follow `AGENTS.md` for versioning, checks, and local installation. Preserve unrelated changes and commit only release work.
2. Build the ZIP in `release/` using `package.sh` through the documented Windows or Linux workflow. Its `--reuse` option is suitable for unchanged paks when their vanilla provenance and contents are verified against the previous release. Check the archive layout, scripts, DLL version, and exclusion of local settings. Copy the verified ZIP to the user's Downloads folder and compare hashes. On Windows use the configured Downloads folder so redirected paths work. Preserve any existing file with different contents.
3. Push the release commit to `origin/dev` and open or reuse the GitHub PR from `dev` to `main`. Link the PR and record checks performed and any remaining in-game validation in its description.
4. Verify the PR head matches the checked release and merge it with a merge commit as soon as GitHub's required checks and approvals allow it. A plain invocation already authorizes this merge. If required checks or reviews are pending, follow them until the merge can proceed. Report a concrete blocker if you cannot proceed. Confirm GitHub reports the PR merged. Tagging and uploading to GitHub Releases or Nexus require a separate request.
