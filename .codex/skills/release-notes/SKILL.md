---
name: release-notes
description: Generate or update project release notes from the newest Git tag and the commits since the previous tag.
---

# Release Notes

Use this skill when the user asks to create, refresh, or summarize a version update log for this project. The output belongs in `docs/update/<tag>.md`.

## Workflow

1. Run the project helper from the repository root:

   ```bash
   .codex/skills/release-notes/scripts/git-release-context.sh
   ```

   Pass a tag explicitly when needed:

   ```bash
   .codex/skills/release-notes/scripts/git-release-context.sh --tag v1.2.0+3
   ```

2. Use the helper output as the source of truth. Identify the selected tag, release date, previous tag, commit range, commit subjects, and changed-file statistics before writing prose.
3. Create or update `docs/update/<tag>.md`. Keep the document in Chinese unless the user requests another language.
4. Include these sections: version, release date/time, overview, new or changed features, bug fixes, build/release notes, and source range. Separate verified fixes (`fix:` commits or explicit bug-fix descriptions) from general improvements. Do not invent fixes, features, or test results that are absent from Git history or repository evidence.
5. For the first tag, when no previous tag exists, treat the complete history reachable from that tag as the release scope and state that it is the initial release. For later tags, use only commits after the previous tag and through the selected tag.
6. Keep the summary user-facing and concise. Preserve commit hashes in the source section so the note remains auditable.

## File conventions

- Store release notes only under `docs/update/`.
- Use the exact Git tag in the filename, for example `docs/update/v1.2.0+3.md`.
- Do not modify tags, commits, or remote branches as part of generating notes.
- Before finishing, verify the target file exists, run `git diff --check`, and report the tag and commit range used.

The helper is deliberately read-only and does not create or modify release-note files; the final wording remains reviewable in the normal project diff.
