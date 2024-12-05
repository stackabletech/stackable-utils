#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
set -x

parse_inputs() {
	RELEASE_TAG=""
	PR_BRANCH=""
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
		*)
			echo "Unknown parameter passed: $1"
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
	PR_BRANCH="pr-$RELEASE_TAG"

	INITIAL_DIR="$PWD"
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)

	echo "Settings: ${PR_BRANCH_NAME}"
}

merge_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		echo "Operator: $operator"
		STATE=$(gh pr view ${PR_BRANCH} -R stackabletech/${operator}-operator --jq '.state' --json state)
		if [[ "$STATE" == "OPEN" ]]; then
			echo "Approving ${operator}"
			gh pr review ${PR_BRANCH} --approve -R stackabletech/${operator}-operator
			gh pr merge ${PR_BRANCH} -R stackabletech/${operator}-operator
		else
			echo "Skipping ${operator}, PR already closed"
		fi
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

merge_products() {
	echo "Operator: $operator"
	STATE=$(gh pr view ${PR_BRANCH} -R stackabletech/${operator}-operator --jq '.state' --json state)
	if [[ "$STATE" == "OPEN" ]]; then
		echo "Approving ${operator}"
		gh pr review ${PR_BRANCH} --approve -R stackabletech/${operator}-operator
		gh pr merge ${PR_BRANCH} -R stackabletech/${operator}-operator
	else
		echo "Skipping ${operator}, PR already closed"
	fi
}

merge() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		merge_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		merge_operators
	fi
}

tag() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		git push "${REPOSITORY}" "${RELEASE_TAG}"
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		git push "${REPOSITORY}" "${RELEASE_TAG}"
	fi
}

check_dependencies() {
	# test required dependencies:
	git config --get user.name
	# check gh authentication: if this fails you will need to e.g. gh auth login
	gh auth status
}

main() {
	parse_inputs "$@"

	# check if tag argument provided
	if [ -z "${RELEASE_TAG}" ]; then
		echo "Usage: create-release-approve-and-tag.sh -t <tag> [-w products|operators|all]"
		exit 1
	fi

	check_dependencies
	merge
	tag
}

main "$@"
