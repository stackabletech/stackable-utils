#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REMOTE="origin"
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
  #-----------------------------------------------------------
  # remove leading and trailing quotes
  #-----------------------------------------------------------
  RELEASE_TAG="${RELEASE_TAG%\"}"
  RELEASE_TAG="${RELEASE_TAG#\"}"
  #----------------------------------------------------------------------------------------------------
  # for a tag of e.g. 23.1.1, the release branch (already created) will be 23.1
  #----------------------------------------------------------------------------------------------------
  RELEASE="$(cut -d'.' -f1,2 <<< "$RELEASE_TAG")"
  RELEASE_BRANCH="release-$RELEASE"

  INITIAL_DIR="$PWD"
  DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
  TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

  echo "Settings: $RELEASE_BRANCH: Push: $PUSH"
}

# Check that the operator repos have been cloned locally, and that the release
# branch and tag exists.
check_operators() {
  while IFS="" read -r OPERATOR || [ -n "$OPERATOR" ]
  do
    echo "Operator: $OPERATOR"
    if [ ! -d "$OPERATOR" ]; then
      echo "Cloning folder: $OPERATOR"
      git clone "git@github.com:stackabletech/${OPERATOR}.git" "$OPERATOR"
    fi
    pushd "$OPERATOR" > /dev/null
    assert_cwd_is_repo "$OPERATOR"
    assert_clean_index "$OPERATOR"
    # TODO (@NickLarsenNZ): Probably need a pull here

    # Note, if this needs to check the branch exists locally, then use:
    # "^[ *]*$RELEASE_BRANCH\$"
    if ! git branch -a | grep "$RELEASE_BRANCH\$"; then
      >&2 echo "Expected release branch is missing: $OPERATOR/$RELEASE_BRANCH"
      exit 1
    fi
    git fetch --tags
    if ! git tag | grep "^$RELEASE_TAG\$"; then
      >&2 echo "Expected tag $RELEASE_TAG missing for operator $OPERATOR"
      exit 1
    fi
    popd > /dev/null
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

# Update the operator changelogs on main, and check they do not differ from
# the changelog in the release branch.
update_operators() {
  while IFS="" read -r OPERATOR || [ -n "$OPERATOR" ]
  do
    pushd "$OPERATOR" > /dev/null
    assert_cwd_is_repo "$OPERATOR"
    assert_clean_index "$OPERATOR"

    git checkout main
    assert_on_branch "main"
    git pull

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
    popd > /dev/null
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

# Check that the docker-images repo has been cloned locally, and that the release
# branch and tag exists.
check_products() {
  if [ ! -d "$DOCKER_IMAGES_REPO" ]; then
    echo "Cloning folder: $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
    git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$DOCKER_IMAGES_REPO"
  fi
  pushd "$DOCKER_IMAGES_REPO" > /dev/null
  assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
  assert_clean_index "$DOCKER_IMAGES_REPO"
  # TODO (@NickLarsenNZ): Probably need a pull here

  # Note, if this needs to check the branch exists locally, then use:
  # "^[ *]*$RELEASE_BRANCH\$"
  if ! git branch -a | grep "$RELEASE_BRANCH\$"; then
    >&2 echo "Expected release branch is missing: $DOCKER_IMAGES_REPO/$RELEASE_BRANCH"
    exit 1
  fi

  git fetch --tags
  # check tags: N.B. look for exact match
  if ! git tag | grep "^$RELEASE_TAG\$"; then
    >&2 echo "Expected tag $RELEASE_TAG missing for $DOCKER_IMAGES_REPO"
    exit 1
  fi
  popd > /dev/null
}

# Update the docker-images changelogs on main, and check they do not differ from
# the changelog in the release branch.
update_products() {
  pushd "$DOCKER_IMAGES_REPO" > /dev/null
  assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
  assert_clean_index "$DOCKER_IMAGES_REPO"

  git checkout main
  assert_on_branch "main"
  git pull

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
  popd > /dev/null
}


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

  if [ ! -d "$TEMP_RELEASE_FOLDER" ]; then
    echo "Creating folder for cloning docker images and operators: [$TEMP_RELEASE_FOLDER]"
    mkdir -p "$TEMP_RELEASE_FOLDER"
  fi

  cd "$TEMP_RELEASE_FOLDER"

  case "$WHAT" in
    products)
      check_products
      echo "Update $DOCKER_IMAGES_REPO main changelog for release $RELEASE_TAG"
      update_products
      ;;
    operators)
      check_operators
      echo "Update the operator main changelog for release $RELEASE_TAG"
      update_operators
      ;;
    all)
      check_products
      echo "Update $DOCKER_IMAGES_REPO main changelog for release $RELEASE_TAG"
      update_products
      check_operators
      echo "Update the operator main changelog for release $RELEASE_TAG"
      update_operators
      ;;
  esac
}

main "$@"
