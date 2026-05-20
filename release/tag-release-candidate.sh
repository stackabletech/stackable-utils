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
	# TODO: Assert we are in sync with the remote release branch (0 ahead, 0 behind after pull)
	git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
	assert_remote_exists "$REMOTE" "$DOCKER_IMAGES_REPO"
	push_branch
	popd > /dev/null
}

# TODO: tag_operator and tag_products share the same logic.
# Extract the common tagging procedure into a shared function.
tag_operator() {
	local operator="$1"
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
	# TODO: Assert we are in sync with the remote release branch (0 ahead, 0 behind after pull)
	git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
	assert_remote_exists "$REMOTE" "$operator"
	push_branch
	popd > /dev/null
}

tag_repos() {
	cd "$TEMP_RELEASE_FOLDER"
	case "$WHAT" in
		products) tag_products ;;
		operators) for_each_operator tag_operator ;;
		all)
			tag_products
			for_each_operator tag_operator
			;;
	esac
}


check_products() {
	ensure_clone "$DOCKER_IMAGES_REPO"
	pushd "$DOCKER_IMAGES_REPO" > /dev/null
	assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
	assert_clean_index "$DOCKER_IMAGES_REPO"
	# TODO (@NickLarsenNZ): Probably need a pull here

	# The release branch should exist (created in a prior step)
	# NOTE: Do we need to check if the branch exists locally?
	# Which branch should we be on here? Does it matter?
	assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"

	assert_tag_not_exists "$RELEASE_TAG"
	popd > /dev/null
}

check_operator() {
	local operator="$1"
	echo "Operator: $operator"
	ensure_clone "$operator"
	pushd "${operator}" > /dev/null
	assert_cwd_is_repo "$operator"
	assert_clean_index "$operator"
	# TODO (@NickLarsenNZ): Probably need a pull here

	# The release branch should exist (created in a prior step)
	# NOTE: Do we need to check if the branch exists locally?
	# Which branch should we be on here? Does it matter?
	assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"
	assert_tag_not_exists "$RELEASE_TAG"
	popd > /dev/null
}

checks() {
	cd "$TEMP_RELEASE_FOLDER"
	case "$WHAT" in
		products) check_products ;;
		operators) for_each_operator check_operator ;;
		all)
			check_products
			for_each_operator check_operator
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

# TODO: Consider moving validation (validate_tag, validate_what) into parse_inputs
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

	RELEASE_TAG="$(strip_double_quotes "$RELEASE_TAG")"

	INITIAL_DIR="$PWD"
	derive_tag_vars "$RELEASE_TAG"

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

	ensure_temp_folder
	check_dependencies

	# sanity checks before we start: folder, branches etc.
	checks

	tag_repos
	cleanup
}

main "$@"
