#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: run this helper inside a Git repository" >&2
  exit 1
}
cd "${ROOT_DIR}"

requested_tag=""
target_tag=""
from_tag=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      requested_tag="${2:-}"
      shift 2
      ;;
    --target-tag)
      target_tag="${2:-}"
      shift 2
      ;;
    --from-tag)
      from_tag="${2:-}"
      shift 2
      ;;
    -h|--help)
      printf '%s\n' \
        'Usage: git-release-context.sh [--tag TAG]' \
        '       git-release-context.sh --target-tag TAG --from-tag TAG' \
        'Print read-only Git evidence for an existing or planned release tag.'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "${target_tag}" && -n "${requested_tag}" ]]; then
  echo "error: use --tag or --target-tag, not both" >&2
  exit 2
fi
if [[ -n "${from_tag}" && -z "${target_tag}" ]]; then
  echo "error: --from-tag requires --target-tag" >&2
  exit 2
fi

tags=()
while IFS= read -r tag_name; do
  [[ -n "${tag_name}" ]] && tags+=("${tag_name}")
done < <(git tag --sort=-v:refname)
if [[ ${#tags[@]} -eq 0 ]]; then
  echo "error: no Git tags found" >&2
  exit 1
fi

if [[ -n "${target_tag}" ]]; then
  tag="${target_tag}"
  if ! git rev-parse --verify --quiet "refs/tags/${from_tag}" >/dev/null; then
    echo "error: source tag not found: ${from_tag}" >&2
    exit 1
  fi
  tag_commit="$(git rev-parse HEAD)"
  tag_date="$(git show -s --format='%aI' HEAD)"
  tag_subject="$(git show -s --format='%s' HEAD)"
  previous_tag="${from_tag}"
  printf 'TAG=%s\n' "${tag}"
  printf 'TAG_COMMIT=%s\n' "${tag_commit}"
  printf 'TAG_DATE=%s\n' "${tag_date}"
  printf 'TAG_SUBJECT=%s\n' "${tag_subject}"
  printf 'PREVIOUS_TAG=%s\n' "${previous_tag}"
  printf 'RANGE=%s..HEAD\n' "${previous_tag}"
  printf 'INITIAL_RELEASE=false\n'
  printf '\n[COMMITS]\n'
  git log --format='%h%x09%aI%x09%s' "${previous_tag}..HEAD"
  printf '\n[STAT]\n'
  git diff --stat "${previous_tag}..HEAD"
  exit 0
fi

tag="${requested_tag:-${tags[0]}}"
tag_index=-1
for index in "${!tags[@]}"; do
  if [[ "${tags[index]}" == "${tag}" ]]; then
    tag_index="${index}"
    break
  fi
done
if [[ "${tag_index}" -lt 0 ]]; then
  echo "error: tag not found: ${tag}" >&2
  exit 1
fi

previous_tag=""
if [[ $((tag_index + 1)) -lt ${#tags[@]} ]]; then
  previous_tag="${tags[$((tag_index + 1))]}"
fi

tag_commit="$(git rev-list -n 1 "${tag}")"
tag_date="$(git for-each-ref --format='%(creatordate:iso-strict)' "refs/tags/${tag}")"
if [[ -z "${tag_date}" ]]; then
  tag_date="$(git show -s --format='%aI' "${tag_commit}")"
fi
tag_subject="$(git show -s --format='%s' "${tag_commit}")"

printf 'TAG=%s\n' "${tag}"
printf 'TAG_COMMIT=%s\n' "${tag_commit}"
printf 'TAG_DATE=%s\n' "${tag_date}"
printf 'TAG_SUBJECT=%s\n' "${tag_subject}"
printf 'PREVIOUS_TAG=%s\n' "${previous_tag}"
if [[ -n "${previous_tag}" ]]; then
  printf 'RANGE=%s..%s\n' "${previous_tag}" "${tag}"
  printf 'INITIAL_RELEASE=false\n'
else
  printf 'RANGE=all history reachable from %s\n' "${tag}"
  printf 'INITIAL_RELEASE=true\n'
fi

printf '\n[COMMITS]\n'
if [[ -n "${previous_tag}" ]]; then
  git log --format='%h%x09%aI%x09%s' "${previous_tag}..${tag}"
else
  git log --format='%h%x09%aI%x09%s' "${tag}"
fi

printf '\n[STAT]\n'
if [[ -n "${previous_tag}" ]]; then
  git diff --stat "${previous_tag}..${tag}"
else
  empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  git diff --stat "${empty_tree}" "${tag}"
fi
