#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REMOTE="origin"

tag_products() {
	# assume that the branch exists and has either been pushed or has been created locally
	pushd "$DOCKER_IMAGES_REPO" > /dev/null
	assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
	assert_clean_index "$DOCKER_IMAGES_REPO"

	# the release branch should already exist
	git switch "$RELEASE_BRANCH"
	assert_on_branch "$RELEASE_BRANCH"
	if $PUSH; then
		git pull
	else
		git pull || echo "Dry-run: remote branch doesn't exist yet..."
		# NOTE (@NickLarsenNZ): We could add a fake commit, but that would poison the current state.
	fi
	assert_on_branch "$RELEASE_BRANCH"
	git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
	assert_remote_exists "$REMOTE" "$DOCKER_IMAGES_REPO"
	push_branch
	popd > /dev/null
}

# TODO: tag_operators and tag_products share the same logic, just with a loop.
# Extract the common tagging procedure into a shared function.
tag_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		pushd "${operator}" > /dev/null
		assert_cwd_is_repo "$operator"
		assert_clean_index "$operator"

		git switch "$RELEASE_BRANCH"
		assert_on_branch "$RELEASE_BRANCH"
		if $PUSH; then
			git pull
		else
			git pull || echo "Dry-run: remote branch doesn't exist yet..."
			# NOTE (@NickLarsenNZ): We could add a fake commit, but that would poison the current state.
		fi
		assert_on_branch "$RELEASE_BRANCH"
		git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
		assert_remote_exists "$REMOTE" "$operator"
		push_branch
		popd > /dev/null
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

tag_repos() {
	cd "$TEMP_RELEASE_FOLDER"
	case "$WHAT" in
		products) tag_products ;;
		operators) tag_operators ;;
		all)
			tag_products
			tag_operators
			;;
	esac
}

check_tag_is_valid() {
	git fetch --tags

	# check tags: N.B. look for exact match
	if git tag --list | grep -E "^$RELEASE_TAG\$"; then
		>&2 echo "Tag $RELEASE_TAG already exists!"
		exit 1
	fi
}

check_products() {
	if [ ! -d "$DOCKER_IMAGES_REPO" ]; then
		echo "Cloning folder: $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
		git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$DOCKER_IMAGES_REPO"
	fi
	pushd "$DOCKER_IMAGES_REPO" > /dev/null
	assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
	assert_clean_index "$DOCKER_IMAGES_REPO"
	# TODO (@NickLarsenNZ): Probably need a pull here

	# The release branch should exist (created in a prior step)
	# NOTE: Do we need to check if the branch exists locally?
	# Which branch should we be on here? Does it matter?
	assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"

	check_tag_is_valid
	popd > /dev/null
}

check_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		echo "Operator: $operator"
		if [ ! -d "${operator}" ]; then
			echo "Cloning folder: $TEMP_RELEASE_FOLDER/${operator}"
			git clone "git@github.com:stackabletech/${operator}.git" "${operator}"
		fi
		pushd "${operator}" > /dev/null
		assert_cwd_is_repo "$operator"
		assert_clean_index "$operator"
		# TODO (@NickLarsenNZ): Probably need a pull here

		# The release branch should exist (created in a prior step)
		# NOTE: Do we need to check if the branch exists locally?
		# Which branch should we be on here? Does it matter?
		assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"
		check_tag_is_valid
		popd > /dev/null
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

checks() {
	cd "$TEMP_RELEASE_FOLDER"
	case "$WHAT" in
		products) check_products ;;
		operators) check_operators ;;
		all)
			check_products
			check_operators
			;;
	esac
}

push_branch() {
	if $PUSH; then
		echo "Pushing tag..."
		git push "${REMOTE}" "${RELEASE_TAG}"
	else
		echo "Dry-run: not pushing tag..."
		git push --dry-run "${REMOTE}" "${RELEASE_TAG}"
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
	check_common_dependencies
}

main() {
	parse_inputs "$@"

	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: tag-release-candidate.sh -t <tag> [-p] [-c] [-w products|operators|all]"
		exit 1
	fi

	validate_tag "$RELEASE_TAG"
	validate_what "$WHAT" "products" "operators" "all"

	if [ ! -d "$TEMP_RELEASE_FOLDER" ]; then
		echo "Creating folder for cloning docker images and operators: [$TEMP_RELEASE_FOLDER]"
		mkdir -p "$TEMP_RELEASE_FOLDER"
	fi

	check_dependencies

	# sanity checks before we start: folder, branches etc.
	checks

	tag_repos
	cleanup
}

main "$@"
