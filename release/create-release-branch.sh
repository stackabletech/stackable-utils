#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
# set -x

REMOTE="origin"
#----------------------------------------------------------------------------------------------------
# tags should be semver-compatible e.g. 23.1 and not 23.01
# this is needed for cargo commands to work properly: although it is not strictly needed
# for the name of the release branch, the branch naming will be consistent with the cargo versioning.
#----------------------------------------------------------------------------------------------------
RELEASE_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])$"

update_products() {
  if [ -d "$BASE_DIR/$DOCKER_IMAGES_REPO" ]; then
    echo "Directory exists. Switching to ${RELEASE_BRANCH} branch and Updating..."
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    git fetch && git switch "${RELEASE_BRANCH}" && git pull
  else
    echo "Repo directory ($BASE_DIR/$DOCKER_IMAGES_REPO) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
    git clone --branch main --depth 1 "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$BASE_DIR/$DOCKER_IMAGES_REPO"
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    # try to switch to the release branch (if continuing from someone else), or create it
    git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}"
  fi

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
      git fetch && git switch "${RELEASE_BRANCH}" && git pull
    else
      echo "Repo directory ($BASE_DIR/$operator) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
      git clone --branch main --depth 1 "git@github.com:stackabletech/${operator}.git" "$BASE_DIR/${operator}"
      cd "$BASE_DIR/${operator}"
      # try to switch to the release branch (if continuing from someone else), or create it
      git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}"
    fi
    push_branch "$operator"
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

update_demos() {
  if [ -d "$BASE_DIR/$DEMOS_REPO" ]; then
    cd "$BASE_DIR/$DEMOS_REPO"
    git pull && git switch "${RELEASE_BRANCH}"
  else
    git clone --branch main --depth 1 "git@github.com:stackabletech/${DEMOS_REPO}.git" "$BASE_DIR/$DEMOS_REPO"
    cd "$BASE_DIR/$DEMOS_REPO"
    git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}"
  fi

  # Search and replace known references to stackableRelease, container images, branch references.
  # https://github.com/stackabletech/demos/blob/main/.scripts/update_refs.sh
  .scripts/update_refs.sh commit

  push_branch "$DEMOS_REPO"
}

update_repos() {
  local BASE_DIR="$1";

  if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_products
  fi
  if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_operators
  fi
  if [ "demos" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_demos
  fi
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
  #-----------------------------------------------------------
  # check if tag argument provided
  #-----------------------------------------------------------
  if [ -z "${RELEASE}" ]; then
    echo "Usage: create-release-branch.sh -b <branch> [-p] [-c] [-w products|operators|demos|all]"
    exit 1
  fi
  #-----------------------------------------------------------
  # check if argument matches our tag regex
  #-----------------------------------------------------------
  if [[ ! $RELEASE =~ $RELEASE_REGEX ]]; then
    echo "Provided branch name [$RELEASE] does not match the required regex pattern [$RELEASE_REGEX]"
    exit 1
  fi

  echo "Cloning docker images and operators to [$TEMP_RELEASE_FOLDER]"
  mkdir -p "$TEMP_RELEASE_FOLDER"
  update_repos "$TEMP_RELEASE_FOLDER"
  cleanup "$TEMP_RELEASE_FOLDER"
}

main "$@"
