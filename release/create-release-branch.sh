#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
set -x

BASE_BRANCH="main"
REPOSITORY="origin"
#----------------------------------------------------------------------------------------------------
# tags should be semver-compatible e.g. 23.1 and not 23.01
# this is needed for cargo commands to work properly: although it is not strictly needed
# for the name of the release branch, the branch naming will be consistent with the cargo versioning.
#----------------------------------------------------------------------------------------------------
RELEASE_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])$"

update_products() {
  if [ -d "$BASE_DIR/$DOCKER_IMAGES_REPO" ]; then
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    git pull && git switch "${RELEASE_BRANCH}"
  else
    git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$BASE_DIR/$DOCKER_IMAGES_REPO"
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}" "${REPOSITORY}/${BASE_BRANCH}"
  fi

  push_branch "$DOCKER_IMAGES_REPO"
}

update_operators() {
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    if [ -d "$BASE_DIR/${operator}" ]; then
      cd "$BASE_DIR/${operator}"
      git pull && git switch "${RELEASE_BRANCH}"
    else
      git clone --branch main --depth 1 "git@github.com:stackabletech/${operator}.git" "$BASE_DIR/${operator}"
      cd "$BASE_DIR/${operator}"
      git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}" "${REPOSITORY}/${BASE_BRANCH}"
    fi
    push_branch "$operator"
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

update_repos() {
  local BASE_DIR="$1";

  if [ "products" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
    update_products
  fi
  if [ "operators" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
    update_operators
  fi
}

push_branch() {
  local REMOTE="$1";
  if $PUSH; then
    echo "Pushing to $REMOTE"
    git push -u "${REPOSITORY}" "${RELEASE_BRANCH}"
  else
    echo "Dry run pushing to $REMOTE"
    git push --dry-run -u "${REPOSITORY}" "${RELEASE_BRANCH}"
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
  TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

  echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"
  #-----------------------------------------------------------
  # check if tag argument provided
  #-----------------------------------------------------------
  if [ -z "${RELEASE}" ]; then
    echo "Usage: create-release-branch.sh -b <branch> [-p] [-c] [-w both|products|operators]"
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
