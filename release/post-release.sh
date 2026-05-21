#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

REMOTE="origin"
PR_MSG="> [!CAUTION]
> ## DO NOT MERGE WITHOUT MANUAL CHECKING!
> This PR contains information about commits have been cherry-picked to the release branch from the main branch, and may not reflect the correct chronology. Please check!"
# TODO: Consider moving validation (validate_tag, validate_what) into parse_inputs
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
  RELEASE_TAG="$(strip_double_quotes "$RELEASE_TAG")"

  INITIAL_DIR="$PWD"
  derive_tag_vars "$RELEASE_TAG"

  echo "Settings: $RELEASE_BRANCH: Push: $PUSH"
}

# Check that an operator repo has been cloned locally, and that the release
# branch and tag exists.
check_operator() (
  local OPERATOR="$1"
  echo "Operator: $OPERATOR"
  ensure_clone "$OPERATOR"
  cd "$OPERATOR"
  assert_cwd_is_repo "$OPERATOR"
  assert_clean_index "$OPERATOR"
  # TODO (@NickLarsenNZ): Probably need a pull here

  # The release branch should exist (created in a prior step)
  # NOTE: Do we need to check if the branch exists locally?
  assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"
  git fetch --tags
  if ! git tag | grep "^$RELEASE_TAG\$"; then
    >&2 echo "Expected tag $RELEASE_TAG missing for operator $OPERATOR"
    exit 1
  fi
)


# Update an operator's changelog on main, and check it does not differ from
# the changelog in the release branch.
update_operator() (
  local OPERATOR="$1"
  cd "$OPERATOR"
  assert_cwd_is_repo "$OPERATOR"
  assert_clean_index "$OPERATOR"

  git checkout main
  assert_on_branch "main"
  git pull
  # TODO: Assert we are in sync with origin/main (0 ahead, 0 behind after pull)

  # New branch that updates the CHANGELOG
  CHANGELOG_BRANCH="chore/update-changelog-from-release-$RELEASE_TAG"
  # Branch out from main
  git switch -c "$CHANGELOG_BRANCH"
  assert_on_branch "$CHANGELOG_BRANCH"
  # Checkout CHANGELOG changes from the release tag
  git checkout "$RELEASE_TAG" -- CHANGELOG.md
  # Ensure only the CHANGELOG has been modified and there
  # are no conflicts.
  CHANGELOG_MODIFIED=$(git status --short)
  if [ "M  CHANGELOG.md" != "$CHANGELOG_MODIFIED" ]; then
    echo "Failed to update CHANGELOG.md in main for operator $OPERATOR"
    exit 1
  fi
  # Commit the updated CHANGELOG.
  git add CHANGELOG.md
  git commit -sm "Update CHANGELOG.md from release $RELEASE_TAG"
  assert_clean_index "$OPERATOR"
  # Maybe push and create pull request
  assert_remote_exists "$REMOTE" "$OPERATOR"
  if "$PUSH"; then
    git push -u "${REMOTE}" "${CHANGELOG_BRANCH}"
    gh pr create --reviewer stackabletech/developers --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
  else
    echo "Dry-run: not pushing..."
    git push --dry-run "${REMOTE}" "${CHANGELOG_BRANCH}"
    gh pr create --reviewer stackabletech/developers --dry-run --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
  fi
)

# Check that the docker-images repo has been cloned locally, and that the release
# branch and tag exists.
check_products() (
  ensure_clone "$DOCKER_IMAGES_REPO"
  cd "$DOCKER_IMAGES_REPO"
  assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
  assert_clean_index "$DOCKER_IMAGES_REPO"
  # TODO (@NickLarsenNZ): Probably need a pull here

  # The release branch should exist (created in a prior step)
  # NOTE: Do we need to check if the branch exists locally?
  assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"

  git fetch --tags
  # check tags: N.B. look for exact match
  if ! git tag | grep "^$RELEASE_TAG\$"; then
    >&2 echo "Expected tag $RELEASE_TAG missing for $DOCKER_IMAGES_REPO"
    exit 1
  fi
)

# Update the docker-images changelogs on main, and check they do not differ from
# the changelog in the release branch.
update_products() (
  cd "$DOCKER_IMAGES_REPO"
  assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
  assert_clean_index "$DOCKER_IMAGES_REPO"

  git checkout main
  assert_on_branch "main"
  git pull
  # TODO: Assert we are in sync with origin/main (0 ahead, 0 behind after pull)

  # New branch that updates the CHANGELOG
  CHANGELOG_BRANCH="chore/update-changelog-from-release-$RELEASE_TAG"
  # Branch out from main
  git switch -c "$CHANGELOG_BRANCH"
  assert_on_branch "$CHANGELOG_BRANCH"
  # Checkout CHANGELOG changes from the release tag
  git checkout "$RELEASE_TAG" -- CHANGELOG.md
  # Ensure only the CHANGELOG has been modified and there
  # are no conflicts.
  CHANGELOG_MODIFIED=$(git status --short)
  if [ "M  CHANGELOG.md" != "$CHANGELOG_MODIFIED" ]; then
    echo "Failed to update CHANGELOG.md in main for $DOCKER_IMAGES_REPO"
    exit 1
  fi
  # Commit the updated CHANGELOG.
  git add CHANGELOG.md
  git commit -sm "Update CHANGELOG.md from release $RELEASE_TAG"
  assert_clean_index "$DOCKER_IMAGES_REPO"
  # Maybe push and create pull request
  assert_remote_exists "$REMOTE" "$DOCKER_IMAGES_REPO"
  if "$PUSH"; then
    git push -u "${REMOTE}" "${CHANGELOG_BRANCH}"
    gh pr create --reviewer stackabletech/developers --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
  else
    echo "Dry-run: not pushing..."
    git push --dry-run "${REMOTE}" "${CHANGELOG_BRANCH}"
    gh pr create --reviewer stackabletech/developers --dry-run --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
  fi
)


main() {
  parse_inputs "$@"

  if [ -z "${RELEASE_TAG}" ]; then
    >&2 echo "Usage: post-release.sh -t <tag> [-p] [-w products|operators|all]"
    exit 1
  fi

  # Post-release is only for final releases, not release candidates.
  validate_tag --no-rc "$RELEASE_TAG"
  validate_what "$WHAT" "products" "operators" "all"
  check_common_dependencies

  ensure_temp_folder
  cd "$TEMP_RELEASE_FOLDER"

  case "$WHAT" in
    products)
      check_products
      echo "Update $DOCKER_IMAGES_REPO main changelog for release $RELEASE_TAG"
      update_products
      ;;
    operators)
      for_each_operator check_operator
      echo "Update the operator main changelog for release $RELEASE_TAG"
      for_each_operator update_operator
      ;;
    all)
      check_products
      echo "Update $DOCKER_IMAGES_REPO main changelog for release $RELEASE_TAG"
      update_products
      for_each_operator check_operator
      echo "Update the operator main changelog for release $RELEASE_TAG"
      for_each_operator update_operator
      ;;
  esac
}

main "$@"
