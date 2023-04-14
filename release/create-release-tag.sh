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

tag_products() {
  # assume that the branch exists and has either been pushed or has been created locally
  cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  #-----------------------------------------------------------
  # the release branch should already exist
  #-----------------------------------------------------------
  git switch "$RELEASE_BRANCH"
  update_product_images_changelogs
  # TODO where to conduct the tag-not-already-exists check?
  git tag "$RELEASE_TAG"
  push_branch
}

tag_operators() {
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    cd "${TEMP_RELEASE_FOLDER}/${operator}"
    git switch "$RELEASE_BRANCH"

    # Update git submodules if needed
    if [ -f .gitmodules ]; then
      git submodule update --recursive --init
    fi

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
    push_branch
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

tag_repos() {
  if [ "products" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
    tag_products
  fi
  if [ "operators" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
    tag_operators
  fi
}

check_products() {
  if [ ! -d "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO" ]; then
    echo "Expected folder is missing: $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
    exit 1
  fi
  cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  #-----------------------------------------------------------
  # the up-to-date release branch has already been pulled
  # N.B. look for exact match (no -rcXXX)
  #-----------------------------------------------------------
  BRANCH_EXISTS=$(git branch -r | grep -E "$RELEASE_BRANCH$")

  if [ -z "${BRANCH_EXISTS}" ]; then
    echo "Expected release branch is missing: $RELEASE_BRANCH"
    exit 1
  fi

  git fetch --tags

  # N.B. look for exact match (no -rcXXX)
  TAG_EXISTS=$(git tag -l | grep -E "$RELEASE_TAG&")
  if [ -n "$TAG_EXISTS" ]; then
    echo "Tag $RELEASE_TAG already exists in $DOCKER_IMAGES_REPO"
    exit 1
  fi
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
    BRANCH_EXISTS=$(git branch -r | grep "$RELEASE_BRANCH")
    if [ -z "${BRANCH_EXISTS}" ]; then
      echo "Expected release branch is missing: ${operator}/$RELEASE_BRANCH"
      exit 1
    fi
    git fetch --tags
    TAG_EXISTS=$(git tag | grep "$RELEASE_TAG")
    if [ -n "${TAG_EXISTS}" ]; then
      echo "Tag $RELEASE_TAG already exists in ${operator}"
      exit 1
    fi
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

checks() {
  if [ "products" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
    check_products
  fi
  if [ "operators" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
    check_operators
  fi
}

update_code() {
  echo "Updating antora docs for $1"
  # antora version should be major.minor, not patch level
  yq -i ".version = \"${RELEASE}\"" "$1/docs/antora.yml"
  yq -i '.prerelease = false' "$1/docs/antora.yml"

  # Not all operators have a getting started guide
  # that's why we verify if templating_vars.yaml exists.
  if [ -f "$1/docs/templating_vars.yaml" ]; then
    yq -i "(.versions.[] | select(. == \"*nightly\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"
    yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" "$1/docs/templating_vars.yaml"
    yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" "$1/docs/templating_vars.yaml"
  fi

  #--------------------------------------------------------------------------
  # Replace .spec.image.stackableVersion for getting-started examples.
  # N.B. yaml files should contain a single document.
  #--------------------------------------------------------------------------
  if [ -d "$1/docs/modules/getting_started/examples/code" ]; then
    for file in $(find "$1/docs/modules/getting_started/examples/code" -name "*.yaml"); do
      yq -i "(.spec | select(has(\"image\")).image | (select(has(\"stackableVersion\")).stackableVersion)) = \"${RELEASE_TAG}\"" "$file"
    done
  fi

    #--------------------------------------------------------------------------
    # Replace .spec.image.stackableVersion for kuttl tests.
    # Use sed as yq does not process .j2 file syntax properly.
    #--------------------------------------------------------------------------
    # TODO old product images won't be tested any longer
    if [ -f "$1/tests/test-definition.yaml" ]; then
      # e.g. 2.2.4-stackable0.5.0 -> 2.2.4-stackable23.1
      sed -i "s/-stackable.*/-stackable${RELEASE_TAG}/" "$1/tests/test-definition.yaml"
    fi

    #--------------------------------------------------------------------------
    # Replace "nightly" link so the documentation refers to the current version
    #--------------------------------------------------------------------------
    for file in $(find "$1/docs" -name "*.adoc"); do
      sed -i "s/nightly@home/home/g" "$file"
    done
}

push_branch() {
  if $PUSH; then
    echo "Pushing changes..."
    git push "${REPOSITORY}" "${RELEASE_BRANCH}"
    git push "${REPOSITORY}" "${RELEASE_TAG}"
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

update_product_images_changelogs() {
  TODAY=$(date +'%Y-%m-%d')
  sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_TAG] - $TODAY/I" ./**/CHANGELOG.md
}

parse_inputs() {
  RELEASE_TAG=""
  PUSH=false
  CLEANUP=false
  WHAT=""

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -t|--tag) RELEASE_TAG="$2"; shift ;;
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
  if [ -z "${RELEASE_TAG}" ]; then
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

  # sanity checks before we start: folder, branches etc.
  # deactivate -e so that piped commands can be used
  set +e
  checks
  set -e

  echo "Cloning docker images and operators to [$TEMP_RELEASE_FOLDER]"
  tag_repos
  cleanup
}

main "$@"
