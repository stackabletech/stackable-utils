#!/usr/bin/env bash
#----------------------------------------------------------------------------------------------------
# Usage: create-release-tag.sh -t <release-tag> [-p] [-c]
#
# -t <release-tag> : e.g. "23.1.42"
# [-p]: push changes (otherwise is effectively a dry run)
# [-c]: cleanup i.e. delete temporary folder(s)
# This script requires https://github.com/mikefarah/yq (not to be confused with https://github.com/kislyuk/yq)
#
# What this script does:
# - checks that the release argument is valid (e.g. semver-compatible, major/minor/patch levels)
# - strips this argument of any leading or trailing quote marks and derives the corresponding branch name
# - for docker images:
#   - creates a new folder in a temporary folder and clones the images repository
#   - switches to the release branch
#   - tags the branch and pushes it if the push argument is provided
# - for operators:
#   - iterates over a list of operator repository names (config.yaml), and for each one:
#   - creates a new folder in a temporary folder and clones the operator repository
#   - switches to the release branch
#   - makes the following changes:
#     - adapts the versions in all cargo.toml to <release-tag> argument
#     - adapts the versions in all helm charts to <release-tag> argument
#     - updates the workspace
#     - rebuilds the helm charts
#     - bumps the changelog
#     - adapts the versions in CRDs in the getting started section to <release-tag> argument
#     - runs the templating script to propagate changes to script files
#   - creates a commit in the branch (i.e. the changes are valid for the branch lifetime)
#   - pushes the commit if the push argument is provided
#----------------------------------------------------------------------------------------------------
set -euo pipefail
set -x
#-----------------------------------------------------------
# tags should be semver-compatible e.g. 23.1.1 not 23.01.1
# this is needed for cargo commands to work properly
#-----------------------------------------------------------
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"
REPOSITORY="origin"

clone_and_tag_repos() {
  mkdir -p "$TEMP_RELEASE_FOLDER" && cd "$TEMP_RELEASE_FOLDER"
  git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git"
  cd "$DOCKER_IMAGES_REPO"
  #-----------------------------------------------------------
  # the release branch should already exist
  #-----------------------------------------------------------
  git pull && git switch "$RELEASE_BRANCH"
  # TODO where to conduct the tag-not-already-exists check?
  git tag "$RELEASE_TAG"
  push_branch

  cd "$TEMP_RELEASE_FOLDER"

  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo "Cloning ${operator}..."
    git clone "git@github.com:stackabletech/${operator}.git"
    cd "$operator"
    git pull && git switch "$RELEASE_BRANCH"

    CARGO_VERSION="$INITIAL_DIR"/release/cargo-version.py
    $CARGO_VERSION --set "$RELEASE_TAG"
    cargo update --workspace
    make regenerate-charts

    update_code "$TEMP_RELEASE_FOLDER/${operator}"
    #-----------------------------------------------------------
    # ensure .j2 changes are resolved
    #-----------------------------------------------------------
    "$TEMP_RELEASE_FOLDER/${operator}"/scripts/docs_templating.sh
    #-----------------------------------------------------------
    # inserts a single line with tag and date
    #-----------------------------------------------------------
    update_changelog "$TEMP_RELEASE_FOLDER/${operator}"

    git commit -am "release $RELEASE_TAG"
    git tag "$RELEASE_TAG"
    #push_branch
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

update_code() {
  # TODO put this in the branch script if the versions are always non-patch level?
  yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" "$1/docs/templating_vars.yaml"
  yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" "$1/docs/templating_vars.yaml"
  #-----------------------------------------------------------
  # Replace spec.version for *.stackable.tech documents
  #-----------------------------------------------------------
  for file in "$1"/docs/modules/getting_started/examples/code/*.yaml; do
    if yq ".apiVersion | select(. | contains(\"stackable.tech\")) | parent | .spec | select (. | has(\"version\"))" "$file" | grep version
    then
      yq -i ".spec.version = \"${RELEASE_TAG}\"" "$file"
    fi
  done
}

push_branch() {
  if $PUSH; then
    echo "Pushing changes..."
    git push "${REPOSITORY}" "${RELEASE_BRANCH}"
    git push --tags
    git switch main
  else
    echo "(Dry-run: not pushing...)"
  fi
}

cleanup() {
  if $CLEANUP; then
    echo "Cleaning up..."
    rm -rf "$TEMP_RELEASE_FOLDER"
  fi
}

update_changelog() {
  TODAY=$(date +'%Y-%m-%d')
  sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_TAG] - $TODAY/I" "$1"/CHANGELOG.md
}

parse_inputs() {
  RELEASE_TAG="xxx"
  PUSH=false
  CLEANUP=false

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -t|--tag) RELEASE_TAG="$2"; shift ;;
          -p|--push) PUSH=true ;;
          -c|--cleanup) CLEANUP=true ;;
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

  echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"
  #-----------------------------------------------------------
  # check if tag argument provided
  #-----------------------------------------------------------
  if [ -z ${RELEASE_TAG+x} ]; then
    echo "Usage: create-release-tag.sh -t <tag>"
    exit 1
  fi
  #-----------------------------------------------------------
  # check if argument matches our tag regex
  #-----------------------------------------------------------
  if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
    echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
    exit 1
  fi

  echo "Cloning docker images and operators to [$TEMP_RELEASE_FOLDER]"
  clone_and_tag_repos
  cleanup
}

main "$@"
