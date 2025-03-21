#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
set -x

# tags should be semver-compatible e.g. 23.1.1 not 23.01.1
# this is needed for cargo commands to work properly
# optional release-candidate suffixes are in the form:
#	- rc-1, e.g. 23.1.1-rc1, 23.12.1-rc12 etc.
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+(-rc[0-9]+)?$"
REPOSITORY="origin"

tag_products() {
	# assume that the branch exists and has either been pushed or has been created locally
	cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

	# the PR branch should already exist
	git switch "$RELEASE_BRANCH"
	git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
	push_branch
}

tag_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		cd "${TEMP_RELEASE_FOLDER}/${operator}"
		git switch "$RELEASE_BRANCH"
		git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
		push_branch
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

tag_repos() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		tag_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		tag_operators
	fi
}

check_tag_is_valid() {
	git fetch --tags

	# check tags: N.B. look for exact match
	TAG_EXISTS=$(git tag --list | grep -E "$RELEASE_TAG$")
	if [ -n "$TAG_EXISTS" ]; then
		>&2 echo "Tag $RELEASE_TAG already exists!"
		exit 1
	fi
}

check_products() {
	if [ ! -d "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO" ]; then
		echo "Cloning folder: $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  		# $TEMP_RELEASE_FOLDER has already been created in main()
  		git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
	fi
	cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

	# switch to the release branch, which should exist as tagging
	# is subsequent to creating the branch.
	BRANCH_EXISTS=$(git branch -a | grep -E "$RELEASE_BRANCH$")

	if [ -z "${BRANCH_EXISTS}" ]; then
		>&2 echo "Expected release branch is missing: $RELEASE_BRANCH"
		exit 1
	fi

	check_tag_is_valid
}

check_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		echo "Operator: $operator"
		if [ ! -d "$TEMP_RELEASE_FOLDER/${operator}" ]; then
			echo "Cloning folder: $TEMP_RELEASE_FOLDER/${operator}"
			# $TEMP_RELEASE_FOLDER has already been created in main()
			git clone "git@github.com:stackabletech/${operator}.git" "$TEMP_RELEASE_FOLDER/${operator}"

		fi
		cd "$TEMP_RELEASE_FOLDER/${operator}"
		BRANCH_EXISTS=$(git branch -a | grep -E "$RELEASE_BRANCH$")
		if [ -z "${BRANCH_EXISTS}" ]; then
			>&2 echo "Expected release branch is missing: ${operator}/$RELEASE_BRANCH"
			exit 1
		fi
		check_tag_is_valid
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

checks() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		check_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		check_operators
	fi
}

push_branch() {
	if $PUSH; then
		echo "Pushing changes..."
		git push "${REPOSITORY}" "${RELEASE_TAG}"
	else
		echo "(Dry-run: not pushing...)"
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

	while [[ "$#" -gt 0 ]]; do
		case $1 in
		-t | --tag)
			RELEASE_TAG="$2"
			shift
			;;
		-w | --what)
			WHAT="$2"
			shift
			;;
		-p | --push) PUSH=true ;;
		-c | --cleanup) CLEANUP=true ;;
		*)
			>&2 echo "Unknown parameter passed: $1"
			exit 1
			;;
		esac
		shift
	done

	# remove leading and trailing quotes
	RELEASE_TAG="${RELEASE_TAG%\"}"
	RELEASE_TAG="${RELEASE_TAG#\"}"

	# for a tag of e.g. 23.1.1, the release branch (already created) will be 23.1
	RELEASE="$(cut -d'.' -f1,2 <<< "$RELEASE_TAG")"
	RELEASE_BRANCH="release-$RELEASE"
	INITIAL_DIR="$PWD"
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
	TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

	echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

check_dependencies() {
	# check for a globally configured git user
	git_user=$(git config --global --includes --get user.name)
	git_email=$(git config --global --includes --get user.email)
	echo "global git user: $git_user <$git_email>"

	if [ -z "$git_user" ] || [ -z "$git_email" ]; then
		>&2 echo "Error: global git user name/email is not set."
		exit 1
	else
		echo "Is this correct? (y/n)"
		read -r response
		if [[ "$response" == "y" || "$response" == "Y" ]]; then
			echo "Proceeding with $git_user <$git_email>"
		else
			>&2 echo "User not accepted. Exiting."
			exit 1
		fi
	fi

	# check gh authentication: if this fails you will need to e.g. gh auth login
	gh auth status
	yq --version
	python --version
	cargo --version
	cargo set-version --version
	# check for jinja2-cli including pyyaml package
	jinja2 --version
	python -m pip show pyyaml
}

main() {
	parse_inputs "$@"

	# check if tag argument provided
	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: create-release-candidate-branch.sh -t <tag> [-p] [-c] [-w products|operators|all]"
		exit 1
	fi

	# check if argument matches our tag regex
	if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
		>&2 echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
		exit 1
	fi

	if [ ! -d "$TEMP_RELEASE_FOLDER" ]; then
	  	echo "Creating folder for cloning docker images and operators: [$TEMP_RELEASE_FOLDER]"
  		mkdir -p "$TEMP_RELEASE_FOLDER"
	fi

	check_dependencies

	# sanity checks before we start: folder, branches etc.
	# deactivate -e so that piped commands can be used
	set +e
	checks
	set -e

	tag_repos
	cleanup
}

main "$@"
