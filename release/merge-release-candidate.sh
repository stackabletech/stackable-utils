#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

parse_inputs() {
	RELEASE_TAG=""
	PUSH=false
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
		-p | --push) PUSH=true ;;
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
	# N.B. this has to match what is used in other scripts
	PR_BRANCH="pr-$RELEASE_TAG"

	INITIAL_DIR="$PWD"
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)

	echo "Settings: ${PR_BRANCH}: Push: $PUSH:"
}

merge_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		echo "Operator: $operator"
		STATE=$(gh pr view "${PR_BRANCH}" -R stackabletech/"${operator}" --jq '.state' --json state)
		if [[ "$STATE" == "OPEN" ]]; then
			echo "Processing ${operator} in branch ${PR_BRANCH} with state ${STATE}"
			if $PUSH; then
				echo "Reviewing and merging..."
				gh pr review "${PR_BRANCH}" --approve -R stackabletech/"${operator}"
				gh pr merge "${PR_BRANCH}" --delete-branch --squash -R stackabletech/"${operator}"
			else
				echo "Dry-run: not reviewing/merging..."
			fi
		else
			echo "Skipping ${operator}, PR already closed"
		fi
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

merge_products() {
	echo "Products: $DOCKER_IMAGES_REPO"
	STATE=$(gh pr view "${PR_BRANCH}" -R stackabletech/"${DOCKER_IMAGES_REPO}" --jq '.state' --json state)
	if [[ "$STATE" == "OPEN" ]]; then
		echo "Processing ${DOCKER_IMAGES_REPO} in branch ${PR_BRANCH} with state ${STATE}"
		if $PUSH; then
			echo "Reviewing and merging..."
			gh pr review "${PR_BRANCH}" --approve -R stackabletech/"${DOCKER_IMAGES_REPO}"
			gh pr merge "${PR_BRANCH}" --delete-branch --squash -R stackabletech/"${DOCKER_IMAGES_REPO}"
		else
			echo "Dry-run: not reviewing/merging..."
		fi
	else
		echo "Skipping ${DOCKER_IMAGES_REPO}, PR already closed"
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
}

main() {
	parse_inputs "$@"

	# check if tag argument provided
	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: create-release-merge-and-tag.sh -t <tag> [-w products|operators|all]"
		exit 1
	fi

	check_dependencies
	merge
}

main "$@"
