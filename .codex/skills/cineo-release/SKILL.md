---
name: cineo-release
description: Prepare a Cineo release by choosing a new or rebuilt public version, generating release notes, publishing with Makefile, and verifying the GitHub Release artifacts.
---

# Cineo Release

Use this skill when the user asks to publish the current Cineo Flutter project, rebuild the current version, migrate a release tag, or prepare Android/iOS artifacts in GitHub Releases.

## Version decision

Before changing files or pushing anything, inspect `Makefile`, `pubspec.yaml`, existing Git tags, and the current branch. Tell the user:

- current public version, for example `1.0.3`;
- current internal build number, for example `4`;
- newest existing release tag;
- whether the requested operation is a new version or a rebuild of the current public version.

Check `git status` before preparing the release. Do not publish over unrelated
uncommitted application changes. Ask the user to commit those changes first,
because release-note evidence is based on committed Git history and the
publish script intentionally rejects unfinished files.

Ask the user to choose one of these two operations when the request is ambiguous:

1. **New version**: select a new `X.Y.Z` public version. Keep or increase `BUILD_NUMBER` as appropriate, but never reuse an existing `vX.Y.Z` tag.
2. **Rebuild current version**: keep the same public `X.Y.Z` and use `REBUILD=1`. This deliberately moves the existing `vX.Y.Z` tag to the newest commit and updates the existing Release assets.

Do not silently infer a rebuild from an unchanged version. A rebuild changes the commit behind a published tag and is an external mutation.

The project version contract is:

- `Makefile`: `VERSION := X.Y.Z` and `BUILD_NUMBER := N`;
- `pubspec.yaml`: `version: X.Y.Z+N`;
- Git tag and GitHub Release: `vX.Y.Z`;
- Android/iOS build arguments: public version `X.Y.Z` plus internal build number `N`.

## Release-note-first workflow

After the user has selected the operation and target version, generate the release note before publishing. The target tag does not exist yet, so use the existing newest tag as the source and the current `HEAD` as the planned release:

```bash
.codex/skills/release-notes/scripts/git-release-context.sh \
  --target-tag "vX.Y.Z" \
  --from-tag "$(git tag --sort=-v:refname | head -n 1)"
```

Use that read-only output to write `docs/update/vX.Y.Z.md` in Chinese. Include only evidence from the selected commit range: version, update time, overview, changed features, verified bug fixes, build/release notes, and source range. Do not claim a build passed before Actions confirms it.

Read `.codex/skills/release-notes/SKILL.md` before generating the document. It owns the release-note format and evidence rules.

## Publish

Review the target version and generated document with the user before the external operation if the user has not already clearly authorized publishing. Then run one of:

```bash
make publish
```

for a new version, or:

```bash
make publish REBUILD=1
```

The command updates `pubspec.yaml`, commits the version and release note, pushes `main`, and pushes the `vX.Y.Z` tag. GitHub Actions then builds a signed/test-signed Android APK and an unsigned iOS IPA. The final job creates or updates the matching GitHub Release, uses `docs/update/vX.Y.Z.md` as its body, and uploads both artifacts.

Do not use `GH_TOKEN`; the workflow uses the repository-provided `github.token`. Do not manually call the GitHub API to create the Release unless the workflow fails and the user explicitly asks for recovery.

## Verification

After publishing, verify all of the following:

- the workflow for the target tag completed successfully;
- Android and iOS build jobs succeeded;
- the Release is not a draft or prerelease unless requested;
- the Release body includes the generated update note;
- the Release has both APK and unsigned IPA assets;
- the local branch and remote `main` are synchronized.

If the build fails, stop before claiming a release. Inspect the failed job, fix the repository, regenerate the affected note if needed, and use a new version tag or the explicitly authorized `REBUILD=1` path.
