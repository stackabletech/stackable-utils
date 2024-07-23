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
  cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  git switch "$RELEASE_BRANCH"
  git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
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

    # set tag version where relevant
    cargo set-version --offline --workspace "$RELEASE_TAG"

    cargo update --workspace
    make regenerate-charts

    update_code "$TEMP_RELEASE_FOLDER/${operator}"
    #-----------------------------------------------------------
    # ensure .j2 changes are resolved
    #-----------------------------------------------------------
    "$TEMP_RELEASE_FOLDER/${operator}"/scripts/docs_templating.sh

    git commit -sam "release $RELEASE_TAG"    
    git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
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
  #-------------------------------------------------------------
  # $TEMP_RELEASE_FOLDER has been created in the calling routine
  #-------------------------------------------------------------
  git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  #---------------------------------------
  # switch to the release branch
  # N.B. look for exact match
  #---------------------------------------
  BRANCH_EXISTS=$(git branch -r | grep -E "$RELEASE_BRANCH$")

  if [ -z "${BRANCH_EXISTS}" ]; then
    echo "Expected release branch is missing: $RELEASE_BRANCH"
    exit 1
  fi

  git switch "${RELEASE_BRANCH}"
  git fetch --tags
  #---------------------------------------
  # check tags: N.B. look for exact match
  #---------------------------------------
  TAG_EXISTS=$(git tag -l | grep -E "$RELEASE_TAG$")
  if [ -n "$TAG_EXISTS" ]; then
    echo "Tag $RELEASE_TAG already exists in $DOCKER_IMAGES_REPO"
    exit 1
  fi
}

check_operators() {
  #-------------------------------------------------------------
  # $TEMP_RELEASE_FOLDER has been created in the calling routine
  #-------------------------------------------------------------
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo "Operator: $operator"
    git clone "git@github.com:stackabletech/${operator}.git" "$TEMP_RELEASE_FOLDER/${operator}"
    cd "$TEMP_RELEASE_FOLDER/${operator}"

    BRANCH_EXISTS=$(git branch -r | grep -E "$RELEASE_BRANCH$")

    if [ -z "${BRANCH_EXISTS}" ]; then
      echo "Expected release branch is missing: ${operator}/$RELEASE_BRANCH"
      exit 1
    fi
    git switch "${RELEASE_BRANCH}"

    git fetch --tags
    TAG_EXISTS=$(git tag -l | grep -E "$RELEASE_TAG$")
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
  if $PRODUCT_IMAGE_TAGS; then
    echo "Updating release tag in code..."
    if [ -f "$1/tests/test-definition.yaml" ]; then
      # e.g. 2.2.4-stackable23.1 -> 2.2.4-stackable23.1.1, since the release tag will use major.minor only
      sed -i "s/-stackable.*/-stackable${RELEASE_TAG}/" "$1/tests/test-definition.yaml"
    fi
  else
    echo "Skip updating release tag in test-definition.yaml..."
  fi

  if [ -f "$1/docs/templating_vars.yaml" ]; then
    echo "Updating templating_vars.yaml..."
    #-----------------------------------------------------------------------------
    # this should always be done as the templating vars are used for both product
    # versions (can be just major.minor) and helm charts (major.minor.patch). We
    # assume that the tag (e.g. 23.7.1) is applied to an earlier tag in the same
    # release (e.g. 23.7.0) so search+replace on the major.minor tag will suffice.
    # TODO: this may pick up versions of external components as well.
    #-----------------------------------------------------------------------------
    yq -i "(.versions.[] | select(. == \"${RELEASE}*\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"
  fi
}


push_branch() {
  if $PUSH; then
    echo "Pushing changes..."
    git push "${REPOSITORY}" "${RELEASE_BRANCH}"
    git push "${REPOSITORY}" "${RELEASE_TAG}"
    git switch main
  else
    echo "(Dry-run: not pushing...)"
    git push --dry-run "${REPOSITORY}" "${RELEASE_BRANCH}"
    git push --dry-run "${REPOSITORY}" "${RELEASE_TAG}"
  fi
}

cleanup() {
  if $CLEANUP; then
    echo "Cleaning up..."
    rm -rf "$TEMP_RELEASE_FOLDER"
  fi
}

parse_inputs() {
  RELEASE_TAG=""
  PUSH=false
  CLEANUP=false
  WHAT=""
  PRODUCT_IMAGE_TAGS=false

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -t|--tag) RELEASE_TAG="$2"; shift ;;
          -w|--what) WHAT="$2"; shift ;;
          -p|--push) PUSH=true ;;
          -c|--cleanup) CLEANUP=true ;;
          -i|--images) PRODUCT_IMAGE_TAGS=true ;;
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
    echo "Usage: create-bugfix-tag.sh -t <tag>"
    exit 1
  fi
  #-----------------------------------------------------------
  # check if argument matches our tag regex
  #-----------------------------------------------------------
  if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
    echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
    exit 1
  fi

  if [ -d "$TEMP_RELEASE_FOLDER" ]; then
    echo "Folder already exists, please delete it!: $TEMP_RELEASE_FOLDER"
    exit 1
  fi

  echo "Creating folder for cloning docker images and operators: [$TEMP_RELEASE_FOLDER]"
  mkdir -p "$TEMP_RELEASE_FOLDER"

  # sanity checks before we start: folder, branches etc.
  # deactivate -e so that piped commands can be used
  set +e
  checks
  set -e

  tag_repos
  cleanup
}

main "$@"
