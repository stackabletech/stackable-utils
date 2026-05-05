#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

PR_MSG="> [!CAUTION]
> ## DO NOT MERGE WITHOUT MANUAL CHECKING!
> This PR contains information about commits have been cherry-picked to the release branch from the main branch, and may not reflect the correct chronology. Please check!"

parse_inputs() {
  RELEASE_TAG=""
  PUSH=false
  WHAT="all"

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -t|--tag) RELEASE_TAG="$2"; shift ;;
          -w|--what) WHAT="$2"; shift ;;
          -p|--push) PUSH=true ;;
          *) echo "Unknown parameter passed: $1"; exit 1 ;;
      esac
      shift
  done

  RELEASE_TAG="$(strip_quotes "$RELEASE_TAG")"

  INITIAL_DIR="$PWD"
  derive_tag_vars "$RELEASE_TAG"

  echo "Settings: $RELEASE_BRANCH: Push: $PUSH"
}

check_single_operator() {
  local operator="$1"
  ( # subshell to isolate cd
    echo "Operator: $operator"
    ensure_clone "$operator"
    cd "$TEMP_RELEASE_FOLDER/$operator"

    require_clean_worktree "$operator"
    require_release_branch "$operator"

    if ! git ls-remote --tags "$REMOTE" "refs/tags/${RELEASE_TAG}" | grep -q "refs/tags/${RELEASE_TAG}"; then
      >&2 echo "Expected tag $RELEASE_TAG missing for operator $operator"
      exit 1
    fi
  )
}

update_single_operator() {
  local operator="$1"
  ( # subshell to isolate cd
    cd "$TEMP_RELEASE_FOLDER/$operator"

    git checkout main
    git pull

    local changelog_branch="chore/update-changelog-from-release-$RELEASE_TAG"
    git switch -c "$changelog_branch"
    git checkout "$RELEASE_TAG" -- CHANGELOG.md

    local changelog_modified
    changelog_modified=$(git status --short)
    if [ "M  CHANGELOG.md" != "$changelog_modified" ]; then
      echo "Failed to update CHANGELOG.md in main for operator $operator"
      exit 1
    fi

    git add CHANGELOG.md
    git commit -sm "Update CHANGELOG.md from release $RELEASE_TAG"

    if "$PUSH"; then
      git push -u "${REMOTE}" "${changelog_branch}"
      gh pr create --reviewer stackabletech/developers --base main --head "${changelog_branch}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
    else
      echo "Dry-run: not pushing..."
      git push --dry-run "${REMOTE}" "${changelog_branch}"
      gh pr create --reviewer stackabletech/developers --dry-run --base main --head "${changelog_branch}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
    fi
  )
}

check_products() {
  ( # subshell to isolate cd
    ensure_clone "$DOCKER_IMAGES_REPO"
    cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

    require_clean_worktree "$DOCKER_IMAGES_REPO"
    require_release_branch "$DOCKER_IMAGES_REPO"

    if ! git ls-remote --tags "$REMOTE" "refs/tags/${RELEASE_TAG}" | grep -q "refs/tags/${RELEASE_TAG}"; then
      >&2 echo "Expected tag $RELEASE_TAG missing for $DOCKER_IMAGES_REPO"
      exit 1
    fi
  )
}

update_products() {
  ( # subshell to isolate cd
    cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

    git checkout main
    git pull

    local changelog_branch="chore/update-changelog-from-release-$RELEASE_TAG"
    git switch -c "$changelog_branch"
    git checkout "$RELEASE_TAG" -- CHANGELOG.md

    local changelog_modified
    changelog_modified=$(git status --short)
    if [ "M  CHANGELOG.md" != "$changelog_modified" ]; then
      echo "Failed to update CHANGELOG.md in main for $DOCKER_IMAGES_REPO"
      exit 1
    fi

    git add CHANGELOG.md
    git commit -sm "Update CHANGELOG.md from release $RELEASE_TAG"

    if "$PUSH"; then
      git push -u "${REMOTE}" "${changelog_branch}"
      gh pr create --reviewer stackabletech/developers --base main --head "${changelog_branch}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
    else
      echo "Dry-run: not pushing..."
      git push --dry-run "${REMOTE}" "${changelog_branch}"
      gh pr create --reviewer stackabletech/developers --dry-run --base main --head "${changelog_branch}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
    fi
  )
}

main() {
  parse_inputs "$@"

  if [ -z "${RELEASE_TAG}" ]; then
    echo "Usage: post-release.sh [options]"
    echo "-t <tag>"
    echo "-p Push changes. Default: false"
    exit 1
  fi

  # WHAT defaults to "all" so empty is valid here
  if [ -n "$WHAT" ]; then
    validate_what "$WHAT" products operators all
  fi
  validate_tag "$RELEASE_TAG" "$TAG_REGEX_FINAL"

  ensure_temp_folder

  if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    check_products
    echo "Update $DOCKER_IMAGES_REPO main changelog for release $RELEASE_TAG"
    update_products
  fi
  if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    for_each_operator check_single_operator
    echo "Update the operator main changelog for release $RELEASE_TAG"
    for_each_operator update_single_operator
  fi
}

main "$@"
