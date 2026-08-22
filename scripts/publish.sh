#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

REQUESTED_VERSION="${VERSION:-}"
VERSION="${REQUESTED_VERSION}"
BRANCH="${BRANCH:-main}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]]; then
  echo "error: Makefile VERSION must use X.Y.Z+BUILD, for example 1.2.0+12" >&2
  exit 2
fi

if [[ "$(git branch --show-current)" != "${BRANCH}" ]]; then
  echo "error: checkout branch '${BRANCH}' before running make publish" >&2
  exit 1
fi

# A publish may include the intentional VERSION edit in Makefile. All other
# changes must already be committed so the artifact represents a known revision.
dirty_paths="$(git status --porcelain=v1 | sed -E 's/^.. //; s/ -> .*//')"
while IFS= read -r path; do
  [[ -z "${path}" ]] && continue
  if [[ "${path}" != "Makefile" ]]; then
    echo "error: uncommitted change found outside Makefile: ${path}" >&2
    echo "Commit or remove it before running make publish." >&2
    exit 1
  fi
done <<< "${dirty_paths}"

makefile_stash=""
if [[ -n "${dirty_paths}" ]]; then
  makefile_stash="publish-version-$(date +%s)"
  git stash push --quiet --keep-index --message "${makefile_stash}" -- Makefile
fi

restore_makefile() {
  if [[ -n "${makefile_stash}" ]]; then
    git stash pop --quiet || {
      echo "error: could not restore the edited Makefile after syncing Git." >&2
      exit 1
    }
  fi
}
trap restore_makefile EXIT

git fetch origin "${BRANCH}" --tags
git pull --rebase origin "${BRANCH}"

# Restore the user's VERSION line before comparing it with pubspec.yaml.
if [[ -n "${makefile_stash}" ]]; then
  git stash pop --quiet
  makefile_stash=""
  trap - EXIT
else
  # When no version was explicitly requested, use the version from the newly
  # synced branch instead of a value expanded by make before the pull.
  if [[ -z "${REQUESTED_VERSION}" ]]; then
    VERSION="$(perl -ne 'if (/^VERSION\s*:=\s*([0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*)\s*$/) { print "$1\n" }' Makefile)"
  fi
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]]; then
  echo "error: Makefile VERSION must use X.Y.Z+BUILD, for example 1.2.0+12" >&2
  exit 2
fi

current_version="$(perl -ne 'if (/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$/) { print "$1+$2\n" }' pubspec.yaml)"
if [[ -z "${current_version}" ]]; then
  echo "error: cannot read version from pubspec.yaml" >&2
  exit 1
fi

if [[ "${current_version}" != "${VERSION}" ]]; then
  ./scripts/update_version.sh --version "${VERSION}"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  git add Makefile pubspec.yaml
  git commit -m "chore: publish Cineo ${VERSION}"
fi

# Push the newest branch revision first, then move the version tag to it.
git push origin "${BRANCH}"
TAG="v${VERSION}"
if git rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null; then
  echo "error: tag ${TAG} already exists; refusing to overwrite it" >&2
  exit 1
fi
git tag -a "${TAG}" -m "Cineo ${VERSION}" HEAD
git push origin "refs/tags/${TAG}"

echo "Published ${TAG}. GitHub Actions will build Android APK and unsigned iOS IPA from this tag."
