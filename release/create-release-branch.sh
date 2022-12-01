#!/usr/bin/env bash
#
# Usage: create-release-branch.sh <release-tag> [-d]
#
# <release-tag> : e.g. "23.01"
# [-d]: dry run
#
set -e
set -x

BASE_BRANCH="main"
REPOSITORY="origin"

RELEASE_TAG=$1
# remove leading and trailing quotes
RELEASE_TAG="${RELEASE_TAG%\"}"
RELEASE_TAG="${RELEASE_TAG#\"}"

RELEASE_BRANCH="release-$RELEASE_TAG"
echo ${RELEASE_BRANCH}

ensure_release_branch() {
  local STATUS=$(git status -s | grep -v '??')

  if [ "$STATUS" != "" ]; then
    >&2 echo "ERROR Dirty working copy found! Stop."
    exit 1
  fi

  git switch -c ${RELEASE_BRANCH} ${BASE_BRANCH}
}

update_antora() {
  yq -i ".version = \"${RELEASE_TAG}\"" docs/antora.yml
  yq -i '.prerelease = false' docs/antora.yml
  yq -i ".versions[] = ${RELEASE_TAG}" docs/templating_vars.yaml
}

main() {
  # for each callout:
  # - create new release branch based on the tag argument
  # - replace "nightly" with "$RELEASE_TAG" (i.e. with qoutes) in antora.yaml
  # - set pre-release=false in antora.yaml
  # - set version to $RELEASE_TAG (without quotes) in docs_templating.sh

  ensure_release_branch
  update_antora

  git commit -am "release $RELEASE_TAG"
  git tag -a $RELEASE_TAG -m "release $RELEASE_TAG"

  if [ "$#" -eq  "2" ]; then
    if [[ $2 == '-d' ]]; then
      echo "Pushing changes..."
      git push ${REPOSITORY} ${RELEASE_BRANCH}
      git push --tags
      git switch main
    fi
   fi
}

main $@
