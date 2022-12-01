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
NOW_UTC=$(date -u '+%Y%m%d%H%M%S')

RELEASE_TAG=$1
RELEASE_BRANCH="release-$RELEASE_TAG"

CARGO_VERSION=$(dirname -- "${BASH_SOURCE[0]}")/cargo-version.py

ensure_release_branch() {
  local STATUS=$(git status -s | grep -v '??')

  if [ "$STATUS" != "" ]; then
    >&2 echo "ERROR Dirty working copy found! Stop."
    exit 1
  fi

  git switch -c ${RELEASE_BRANCH} ${BASE_BRANCH}
  git push -u ${REPOSITORY} ${RELEASE_BRANCH}
}

maybe_create_github_pr() {
  local MESSAGE=$@
  GH_COMMAND=$(which gh)
  if [ "$GH_COMMAND" != "" ]; then
    gh pr create --base $BASE_BRANCH --head $RELEASE_BRANCH --title "$MESSAGE" --body "$MESSAGE"
  fi
}

update_changelog() {
  local RELEASE_VERSION=$1;

  TODAY=$(date +'%Y-%m-%d')

  sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_VERSION] - $TODAY/I" CHANGELOG.md
}

main() {

  local NEXT_LEVEL=${1:-"release"}
  local PUSH=${2:-true}

  ensure_release_branch

  if [ "$NEXT_LEVEL" == "release" ]; then
    #
    # Release
    #
    $CARGO_VERSION --release
    cargo update --workspace
    make regenerate-charts
    local RELEASE_VERSION=$($CARGO_VERSION --show)
    local DOCS_VERSION=$(echo "${RELEASE_VERSION}" | sed 's/^\([0-9]\+\.[0-9]\+\)\..*$/\1/')

    update_changelog $RELEASE_VERSION

    MESSAGE="release $RELEASE_VERSION"
    git commit -am "release $RELEASE_VERSION"
    git tag -a $RELEASE_VERSION -m "release $RELEASE_VERSION"
    # We don't want to tag the docs in all the cases, as some manual steps might be needed (e.g. updating getting started guides)
    # git tag -a docs/$DOCS_VERSION -m "docs $DOCS_VERSION"

  else
    #
    # Development
    #
    $CARGO_VERSION --next ${NEXT_LEVEL}
    cargo update --workspace
    make regenerate-charts
    local RELEASE_VERSION=$($CARGO_VERSION --show)

    MESSAGE="bump version $RELEASE_VERSION"
    git commit -am "bump version $RELEASE_VERSION"

  fi

  if [ "$PUSH" = "true" ]; then
    git push ${REPOSITORY} ${RELEASE_BRANCH}
    # git push --tags
    maybe_create_github_pr $MESSAGE
    git switch main
  fi
}

main $@
