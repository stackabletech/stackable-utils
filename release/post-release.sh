#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
# set -x

#-----------------------------------------------------------
# tags should be semver-compatible e.g. 23.1.1 not 23.01.1
# this is needed for cargo commands to work properly
#-----------------------------------------------------------
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"
REMOTE="origin"
PR_MSG="> [!CAUTION]
> ## DO NOT MERGE WITHOUT MANUAL CHECKING!
> This PR contains information about commits have been cherry-picked to the release branch from the main branch, and may not reflect the correct chronology. Please check!"
parse_inputs() {
  RELEASE_TAG=""
  PUSH=false
  WHAT="all"

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -t|--tag) RELEASE_TAG="$2"; shift ;;
          -w|--what) WHAT="$2"; shift ;;
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
  DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
  TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

  echo "Settings: $RELEASE_BRANCH: Push: $PUSH"
}

# Check that the operator repos have been cloned locally, and that the release
# branch and tag exists.
check_operators() {
  while IFS="" read -r OPERATOR || [ -n "$OPERATOR" ]
  do
    echo "Operator: $OPERATOR"
    if [ ! -d "$TEMP_RELEASE_FOLDER/$OPERATOR" ]; then
      echo "Cloning folder: $TEMP_RELEASE_FOLDER/$OPERATOR"
      # $TEMP_RELEASE_FOLDER has already been created in main()
      git clone "git@github.com:stackabletech/${OPERATOR}.git" "$TEMP_RELEASE_FOLDER/$OPERATOR"
    fi
    cd "$TEMP_RELEASE_FOLDER/$OPERATOR"

    if ! git diff-index --quiet HEAD --; then
      >&2 echo "Dirty git index for $OPERATOR. Check working tree or staged changes. Exiting."
      exit 2
    fi

    BRANCH_EXISTS=$(git branch -a | grep "$RELEASE_BRANCH")
    if [ -z "$BRANCH_EXISTS" ]; then
      >&2 echo "Expected release branch is missing: $OPERATOR/$RELEASE_BRANCH"
      exit 1
    fi
    git fetch --tags
    TAG_EXISTS=$(git tag | grep "$RELEASE_TAG")
    if [ -z "$TAG_EXISTS" ]; then
      >&2 echo "Expected tag $RELEASE_TAG missing for operator $OPERATOR"
      exit 1
    fi
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

# Update the operator changelogs on main, and check they do not differ from
# the changelog in the release branch.
update_operators() {
  while IFS="" read -r OPERATOR || [ -n "$OPERATOR" ]
  do
    cd "$TEMP_RELEASE_FOLDER/$OPERATOR"
    # New branch that updates the CHANGELOG
    CHANGELOG_BRANCH="chore/update-changelog-from-release-$RELEASE_TAG"
    # Branch out from main
    git switch -c "$CHANGELOG_BRANCH" main
    # Checkout CHANGELOG changes from the release tag
    git checkout "$RELEASE_TAG" -- CHANGELOG.md
    # Ensure only the CHANGELOG has been modified and there
    # are no conflicts.
    CHANGELOG_MODIFIED=$(git status --short)
    if [ "M  CHANGELOG.md" != "$CHANGELOG_MODIFIED" ]; then
      echo "Failed to update CHANGELOG.md in main for operator $OPERATOR"
      exit 1
    fi
    # Commit the updated CHANGELOG.
    git add CHANGELOG.md
    git commit -sm "Update CHANGELOG.md from release $RELEASE_TAG"
    # Maybe push and create pull request
    if "$PUSH"; then
      git push -u "${REMOTE}" "${CHANGELOG_BRANCH}"
      gh pr create --reviewer stackabletech/developers --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
    else
      echo "Dry-run: not pushing..."
      git push --dry-run "${REMOTE}" "${CHANGELOG_BRANCH}"
      gh pr create --reviewer stackabletech/developers --dry-run --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
    fi
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

# Check that the docker-images repo has been cloned locally, and that the release
# branch and tag exists.
check_products() {
  if [ ! -d "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO" ]; then
    echo "Cloning folder: $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
      # $TEMP_RELEASE_FOLDER has already been created in main()
      git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  fi
  cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

  if ! git diff-index --quiet HEAD --; then
    >&2 echo "Dirty git index for $DOCKER_IMAGES_REPO. Check working tree or staged changes. Exiting."
    exit 2
  fi

  BRANCH_EXISTS=$(git branch -a | grep "$RELEASE_BRANCH")
  if [ -z "${BRANCH_EXISTS}" ]; then
    >&2 echo "Expected release branch is missing: $DOCKER_IMAGES_REPO/$RELEASE_BRANCH"
    exit 1
  fi

  git fetch --tags
  TAG_EXISTS=$(git tag | grep "$RELEASE_TAG")
  if [ -z "${TAG_EXISTS}" ]; then
    >&2 echo "Expected tag $RELEASE_TAG missing for $DOCKER_IMAGES_REPO"
    exit 1
  fi
}

# Update the docker-images changelogs on main, and check they do not differ from
# the changelog in the release branch.
update_products() {
  cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  # New branch that updates the CHANGELOG
  CHANGELOG_BRANCH="chore/update-changelog-from-release-$RELEASE_TAG"
  # Branch out from main
  git switch -c "$CHANGELOG_BRANCH" main
  # Checkout CHANGELOG changes from the release tag
  git checkout "$RELEASE_TAG" -- CHANGELOG.md
  # Ensure only the CHANGELOG has been modified and there
  # are no conflicts.
  CHANGELOG_MODIFIED=$(git status --short)
  if [ "M  CHANGELOG.md" != "$CHANGELOG_MODIFIED" ]; then
    echo "Failed to update CHANGELOG.md in main for $DOCKER_IMAGES_REPO"
    exit 1
  fi
  # Commit the updated CHANGELOG.
  git add CHANGELOG.md
  git commit -sm "Update CHANGELOG.md from release $RELEASE_TAG"
  # Maybe push and create pull request
  if "$PUSH"; then
    git push -u "${REMOTE}" "${CHANGELOG_BRANCH}"
    gh pr create --reviewer stackabletech/developers --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
  else
    echo "Dry-run: not pushing..."
    git push --dry-run "${REMOTE}" "${CHANGELOG_BRANCH}"
    gh pr create --reviewer stackabletech/developers --dry-run --base main --head "${CHANGELOG_BRANCH}" --title "chore: Update changelog from release ${RELEASE_TAG}" --body "${PR_MSG}"
  fi
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

  if [ ! -d "$TEMP_RELEASE_FOLDER" ]; then
    echo "Creating folder for cloning docker images and operators: [$TEMP_RELEASE_FOLDER]"
    mkdir -p "$TEMP_RELEASE_FOLDER"
  fi

  if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    # sanity checks before we start: folder, branches etc.
    check_products

    echo "Update $DOCKER_IMAGES_REPO main changelog for release $RELEASE_TAG"
    update_products
  fi
  if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    # sanity checks before we start: folder, branches etc.
    check_operators

    echo "Update the operator main changelog for release $RELEASE_TAG"
    update_operators
  fi

}

main "$@"
