#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

tag_products() {
	( # subshell to isolate cd
		cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

		git switch "$RELEASE_BRANCH"
		if $PUSH; then
			git pull
		else
			git pull || echo "Dry-run: remote branch doesn't exist yet..."
		fi
		git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
		push_tag
	)
}

tag_single_operator() {
	local operator="$1"
	( # subshell to isolate cd
		cd "${TEMP_RELEASE_FOLDER}/${operator}"
		git switch "$RELEASE_BRANCH"
		if $PUSH; then
			git pull
		else
			git pull || echo "Dry-run: remote branch doesn't exist yet..."
		fi
		git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
		push_tag
	)
}

tag_repos() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		tag_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		for_each_operator tag_single_operator
	fi
}

check_products() {
	( # subshell to isolate cd
		ensure_clone "$DOCKER_IMAGES_REPO"
		cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

		require_release_branch "$DOCKER_IMAGES_REPO"
		check_tag_is_valid "$RELEASE_TAG" "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
	)
}

check_single_operator() {
	local operator="$1"
	( # subshell to isolate cd
		echo "Operator: $operator"
		ensure_clone "$operator"
		cd "$TEMP_RELEASE_FOLDER/${operator}"

		require_release_branch "$operator"
		check_tag_is_valid "$RELEASE_TAG" "$TEMP_RELEASE_FOLDER/${operator}"
	)
}

checks() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		check_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		for_each_operator check_single_operator
	fi
}

push_tag() {
	if $PUSH; then
		echo "Pushing changes..."
		git push "$REMOTE" "${RELEASE_TAG}"
	else
		echo "Dry-run: not pushing..."
		git push --dry-run "$REMOTE" "${RELEASE_TAG}"
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

	RELEASE_TAG="$(strip_quotes "$RELEASE_TAG")"

	INITIAL_DIR="$PWD"
	derive_tag_vars "$RELEASE_TAG"

	echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
	parse_inputs "$@"

	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: tag-release-candidate.sh -t <tag> [-p] [-c] [-w products|operators|all]"
		exit 1
	fi

	validate_what "$WHAT" products operators all
	validate_tag "$RELEASE_TAG" "$TAG_REGEX"

	ensure_temp_folder
	check_basic_dependencies

	checks

	tag_repos
	cleanup
}

main "$@"
