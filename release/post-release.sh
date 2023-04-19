#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
set -x
#-----------------------------------------------------------
# tags should be semver-compatible e.g. 23.1.1 not 23.01.1
# this is needed for cargo commands to work properly
#-----------------------------------------------------------
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"
REPOSITORY="origin"

parse_inputs() {
  RELEASE_TAG=""
  PUSH=false

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -t|--tag) RELEASE_TAG="$2"; shift ;;
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
  TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

  echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH"
}

check_operators() {
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo "Operator: $operator"
    if [ ! -d "$TEMP_RELEASE_FOLDER/${operator}" ]; then
      echo "Expected folder is missing: $TEMP_RELEASE_FOLDER/${operator}"
      exit 1
    fi

    cd "$TEMP_RELEASE_FOLDER/${operator}"

    DIRTY_WORKING_COPY=$(git status --short)
    if [ -n "${DIRTY_WORKING_COPY}" ]; then
      echo "Dirty working copy found for operator ${operator}"
      exit 1
    fi
    TAG_EXISTS=$(git tag | grep "$RELEASE_TAG")
    if [ -z "${BRANCH_EXISTS}" ]; then
      echo "Expected release branch is missing: ${operator}/$RELEASE_BRANCH"
      exit 1
    fi
    git fetch --tags
    TAG_EXISTS=$(git tag | grep "$RELEASE_TAG")
    if [ -z "${TAG_EXISTS}" ]; then
      echo "Expected tag $RELEASE_TAG missing for operator ${operator}"
      exit 1
    fi
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

update_main_changelog() {
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    cd "$TEMP_RELEASE_FOLDER/${operator}"
    # New branch that updates the CHANGELOG
    CHANGELOG_BRANCH="update-changelog-from-release-$RELEASE_TAG"
    # Branch out from main
    git switch -c "$CHANGELOG_BRANCH" main
    # Checkout CHANGELOG changes from the release tag
    git checkout "$RELEASE_TAG" -- CHANGELOG.md
    # Ensure only the CHANGELOG has been modified and there
    # are no conflicts.
    CHANGELOG_MODIFIED=$(git status --short)
    if [ "M  CHANGELOG.md" != "$CHANGELOG_MODIFIED" ]; then
      echo "Failed to update CHANGELOG.md in main for operator ${operator}"
      exit 1
    fi
    # Commit the updated CHANGELOG.
    git add CHANGELOG.md
    git commit -m "Update CHANGELOG.md from release $RELEASE_TAG"
    # Maybe push and create pull request
    if "$PUSH"; then
      git push -u "$REPOSITORY" "$CHANGELOG_BRANCH"
      gh pr create --fill --reviewer stackable/developers
    fi
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}


main() {
  parse_inputs "$@"
  #-----------------------------------------------------------
  # check if tag argument provided
  #-----------------------------------------------------------
  if [ -z "${RELEASE_TAG}" ]; then
    echo "Usage: post-release.sh [options]"
    echo "-t <tag>"
    echo "-p Push changes. Default: false"
    exit 1
  fi
  #-----------------------------------------------------------
  # check if argument matches our tag regex
  #-----------------------------------------------------------
  if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
    echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
    exit 1
  fi

  # sanity checks before we start: folder, branches etc.
  # deactivate -e so that piped commands can be used
  set +e
  checks_operators
  set -e

  echo "Update main changelog from release $RELEASE_TAG"
  update_main_changelog
}

main "$@"
