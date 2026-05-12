#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REMOTE="origin"

update_products() {
  if [ -d "$BASE_DIR/$DOCKER_IMAGES_REPO" ]; then
    echo "Directory exists. Switching to ${RELEASE_BRANCH} branch and Updating..."
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
    assert_clean_index "$DOCKER_IMAGES_REPO"
    git pull && git switch "${RELEASE_BRANCH}" # Switch to local branch (remote doesn't yet exist)
  else
    echo "Repo directory ($BASE_DIR/$DOCKER_IMAGES_REPO) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
    git clone --branch main "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$BASE_DIR/$DOCKER_IMAGES_REPO"
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
    # try to switch to the release branch (if continuing from someone else), or create it
    git switch "${RELEASE_BRANCH}" 2> /dev/null || git switch -c "${RELEASE_BRANCH}"
  fi
  assert_on_branch "$RELEASE_BRANCH"

  assert_remote_exists "$REMOTE" "$DOCKER_IMAGES_REPO"
  push_branch "$DOCKER_IMAGES_REPO"

  echo
  echo "Check $BASE_DIR/$DOCKER_IMAGES_REPO"
}

update_operators() {
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    if [ -d "$BASE_DIR/${operator}" ]; then
      echo "Directory exists. Switching to ${RELEASE_BRANCH} branch and Updating..."
      cd "$BASE_DIR/${operator}"
      assert_cwd_is_repo "$operator"
      assert_clean_index "$operator"
      git pull && git switch "${RELEASE_BRANCH}" # Switch to local branch (remote doesn't yet exist)
    else
      echo "Repo directory ($BASE_DIR/$operator) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
      git clone --branch main "git@github.com:stackabletech/${operator}.git" "$BASE_DIR/${operator}"
      cd "$BASE_DIR/${operator}"
      assert_cwd_is_repo "$operator"
      # try to switch to the release branch (if continuing from someone else), or create it
      git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}"
    fi
    assert_on_branch "$RELEASE_BRANCH"
    assert_remote_exists "$REMOTE" "$operator"
    push_branch "$operator"
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

update_demos() {
  if [ -d "$BASE_DIR/$DEMOS_REPO" ]; then
    cd "$BASE_DIR/$DEMOS_REPO"
    assert_cwd_is_repo "$DEMOS_REPO"
    assert_clean_index "$DEMOS_REPO"
    git pull && git switch "${RELEASE_BRANCH}"
  else
    git clone --branch main "git@github.com:stackabletech/${DEMOS_REPO}.git" "$BASE_DIR/$DEMOS_REPO"
    cd "$BASE_DIR/$DEMOS_REPO"
    assert_cwd_is_repo "$DEMOS_REPO"
    git switch "${RELEASE_BRANCH}" 2> /dev/null  || git switch -c "${RELEASE_BRANCH}"
  fi
  assert_on_branch "$RELEASE_BRANCH"

  # Search and replace known references to stackableRelease, container images, branch references.
  # https://github.com/stackabletech/demos/blob/main/.scripts/update_refs.sh
  .scripts/update_refs.sh commit

  assert_remote_exists "$REMOTE" "$DEMOS_REPO"
  push_branch "$DEMOS_REPO"
}

update_repos() {
  local BASE_DIR="$1";

  case "$WHAT" in
    products) update_products ;;
    operators) update_operators ;;
    demos) update_demos ;;
    all)
      update_products
      update_operators
      update_demos
      ;;
  esac
}

push_branch() {
  local REPOSITORY="$1";
  if $PUSH; then
    echo "Pushing changes to $REPOSITORY"
    git push -u "$REMOTE" "$RELEASE_BRANCH"
  else
    echo "Dry-run: not pushing changes to $REPOSITORY"
    git push --dry-run -u "$REMOTE" "$RELEASE_BRANCH"
  fi
}

cleanup() {
  local BASE_DIR="$1";

  if $CLEANUP; then
    echo "Cleaning up..."
    rm -rf "$BASE_DIR"
  fi
}

parse_inputs() {
  RELEASE=""
  PUSH=false
  CLEANUP=false
  WHAT=""

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -b|--branch) RELEASE="$2"; shift ;;
          -w|--what) WHAT="$2"; shift ;;
          -p|--push) PUSH=true ;;
          -c|--cleanup) CLEANUP=true ;;
          *) echo "Unknown parameter passed: $1"; exit 1 ;;
      esac
      shift
  done
  #-----------------------------------------------------------
  # remove leading and trailing quotes
  #-----------------------------------------------------------
  RELEASE="${RELEASE%\"}"
  RELEASE="${RELEASE#\"}"
  RELEASE_BRANCH="release-$RELEASE"

  INITIAL_DIR="$PWD"
  DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
  DEMOS_REPO=$(yq '... comments="" | .demos-repo ' "$INITIAL_DIR"/release/config.yaml)
  TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

  echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"

  if [ -z "${RELEASE}" ]; then
    >&2 echo "Usage: create-release-branch.sh -b <branch> [-p] [-c] [-w products|operators|demos|all]"
    exit 1
  fi

  validate_release_base_version "$RELEASE"
  validate_what "$WHAT" "products" "operators" "demos" "all"
  check_common_dependencies

  echo "Creating temporary working directory if it doesn't exist [$TEMP_RELEASE_FOLDER]"
  mkdir -p "$TEMP_RELEASE_FOLDER"
  update_repos "$TEMP_RELEASE_FOLDER"
  cleanup "$TEMP_RELEASE_FOLDER"
}

main "$@"
