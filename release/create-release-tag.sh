#!/usr/bin/env bash
#
# Usage: create-release-tag.sh <release-tag> [-d]
#
# <release-tag> : e.g. "23.1.42"
# [-d]: dry run
#
# What this script does:
# - Adapt versions in all cargo.toml to <release-tag> argument
# - Adapt versions in all helm charts to <release-tag> argument
# - Bump the changelog
# - Adapt versions in CRDs in the getting started section
set -e
#set -x

RELEASE_TAG=$1
# tags should be semver-compatible e.g. 23.1.1 and not 23.01.1
# this is needed for cargo commands to work properly
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"

# remove leading and trailing quotes
RELEASE_TAG="${RELEASE_TAG%\"}"
RELEASE_TAG="${RELEASE_TAG#\"}"

# for a tag of e.g. 23.1.1 the release branch (already created) will be 23.1
RELEASE="$(cut -d'.' -f1,2 <<<"$RELEASE_TAG")"
RELEASE_BRANCH="release-$RELEASE"
echo "Working release branch: ${RELEASE_BRANCH}"

#DOCKER_IMAGES_REPO="docker-images"
DOCKER_IMAGES_REPO="test-platform-release-images"
TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

INITIAL_DIR="$PWD"

clone_and_tag_repos() {
  mkdir -p "$TEMP_RELEASE_FOLDER" && cd "$TEMP_RELEASE_FOLDER"
  git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git"
  cd "$DOCKER_IMAGES_REPO"
  # the release branch should already exist
  git pull && git switch "$RELEASE_BRANCH"
  #git tag "$RELEASE_TAG"
  #push_branch "$@"

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
    # ensure .j2 changes are resolved
    "$TEMP_RELEASE_FOLDER/${operator}"/scripts/docs_templating.sh

    # inserts a single line with tag and date
    update_changelog "$TEMP_RELEASE_FOLDER/${operator}"

    #git commit -am "release $RELEASE_TAG"
    #git tag "$RELEASE_TAG"
    #push_branch "$@"
  done < "$INITIAL_DIR"/release/operators_to_release.txt
}

update_code() {
  # these 3 instructions would have been executed when the branch was created:
  #yq -i ".version = \"${RELEASE_TAG}\"" "$1/docs/antora.yml"
  #yq -i ".prerelease = false" "$1docs/antora.yml"
  #yq -i ".versions[] = \"${RELEASE_TAG}\"" "$1docs/templating_vars.yaml"

  yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" "$1/docs/templating_vars.yaml"
  yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" "$1/docs/templating_vars.yaml"

  # Replace spec.version for *.stackable.tech documents
  for file in "$1"/docs/modules/getting_started/examples/code/*.yaml; do
    if yq ".apiVersion | select(. | contains(\"stackable.tech\")) | parent | .spec | select (. | has(\"version\"))" "$file" | grep version
    then
      yq -i ".spec.version = \"${RELEASE_TAG}\"" "$file"
    fi
  done
}

push_branch() {
  if [ "$#" -eq  "2" ]; then
    if [[ $2 == '-p' ]]; then
      echo "Pushing changes..."
      git push "${REPOSITORY}" "${RELEASE_BRANCH}"
      git switch main
    fi
  else
    echo "(Dry-run: not pushing...)"
  fi
}

update_changelog() {
  TODAY=$(date +'%Y-%m-%d')
  sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_TAG] - $TODAY/I" "$1"/CHANGELOG.md
}

main() {
  # check if tag argument provided
  if [ -z ${RELEASE_TAG+x} ]; then
    echo "Usage: create-release-tag.sh <tag>"
    exit -1
  fi
  # check if argument matches our tag regex
  if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
    echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
    exit -1
  fi

  echo "Cloning docker images and operators to [$TEMP_RELEASE_FOLDER]"
  clone_and_tag_repos "$@"

  echo "Cleaning up"
  #rm -rf "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  #while IFS="" read -r operator || [ -n "$operator" ]
  #  do
  #    rm -rf "$TEMP_RELEASE_FOLDER/$operator"
  #  done < "$INITIAL_DIR"/release/operators_to_release.txt
}

main "$@"
