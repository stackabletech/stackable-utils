#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
set -x
#-----------------------------------------------------------
# tags should be semver-compatible e.g. 23.1.1 not 23.01.1
# this is needed for cargo commands to work properly
#-----------------------------------------------------------
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"
REPOSITORY="origin"

tag_products() {
	# assume that the branch exists and has either been pushed or has been created locally
	cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
	#-----------------------------------------------------------
	# the release branch should already exist
	#-----------------------------------------------------------
	git switch "$RELEASE_BRANCH"
	update_product_images_changelogs

	git commit -sam "release $RELEASE_TAG"
	git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
	push_branch
}

tag_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		cd "${TEMP_RELEASE_FOLDER}/${operator}"
		git switch "$RELEASE_BRANCH"

		# Update git submodules if needed
		if [ -f .gitmodules ]; then
			git submodule update --recursive --init
		fi

		cargo set-version --offline --workspace "$RELEASE_TAG"
		cargo update --workspace
		# Run via nix-shell for the correct dependencies. Makefile already calls
		# nix stuff, so it shouldn't be a problem for non-nix users.
		nix-shell --run 'make regenerate-charts'
		nix-shell --run 'make regenerate-nix'

		update_code "$TEMP_RELEASE_FOLDER/${operator}"
		#-----------------------------------------------------------
		# ensure .j2 changes are resolved
		#-----------------------------------------------------------
		"$TEMP_RELEASE_FOLDER/${operator}"/scripts/docs_templating.sh
		#-----------------------------------------------------------
		# inserts a single line with tag and date
		#-----------------------------------------------------------
		update_changelog "$TEMP_RELEASE_FOLDER/${operator}"

		git commit -sam "release $RELEASE_TAG"
		git tag -sm "release $RELEASE_TAG" "$RELEASE_TAG"
		push_branch
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

tag_repos() {
	if [ "products" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
		tag_products
	fi
	if [ "operators" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
		tag_operators
	fi
}

check_products() {
	if [ ! -d "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO" ]; then
		echo "Expected folder is missing: $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
		exit 1
	fi
	cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
	#-----------------------------------------------------------
	# the up-to-date release branch has already been pulled
	# N.B. look for exact match (no -rcXXX)
	#-----------------------------------------------------------
	BRANCH_EXISTS=$(git branch -a | grep -E "$RELEASE_BRANCH$")

	if [ -z "${BRANCH_EXISTS}" ]; then
		echo "Expected release branch is missing: $RELEASE_BRANCH"
		exit 1
	fi

	git fetch --tags

	TAG_EXISTS=$(git tag -l | grep -E "$RELEASE_TAG$")
	if [ -n "$TAG_EXISTS" ]; then
		echo "Tag $RELEASE_TAG already exists in $DOCKER_IMAGES_REPO"
		exit 1
	fi
}

check_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		echo "Operator: $operator"
		if [ ! -d "$TEMP_RELEASE_FOLDER/${operator}" ]; then
			echo "Expected folder is missing: $TEMP_RELEASE_FOLDER/${operator}"
			exit 1
		fi
		cd "$TEMP_RELEASE_FOLDER/${operator}"
		BRANCH_EXISTS=$(git branch -a | grep -E "$RELEASE_BRANCH$")
		if [ -z "${BRANCH_EXISTS}" ]; then
			echo "Expected release branch is missing: ${operator}/$RELEASE_BRANCH"
			exit 1
		fi
		git fetch --tags
		TAG_EXISTS=$(git tag -l | grep -E "$RELEASE_TAG$")
		if [ -n "${TAG_EXISTS}" ]; then
			echo "Tag $RELEASE_TAG already exists in ${operator}"
			exit 1
		fi
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

checks() {
	if [ "products" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
		check_products
	fi
	if [ "operators" == "$WHAT" ] || [ "both" == "$WHAT" ]; then
		check_operators
	fi
}

update_code() {
	if [ -d "$1/docs" ]; then
		echo "Updating antora docs for $1"
		# antora version should be major.minor, not patch level
		yq -i ".version = \"${RELEASE}\"" "$1/docs/antora.yml"
		yq -i '.prerelease = false' "$1/docs/antora.yml"

		# Not all operators have a getting started guide
		# that's why we verify if templating_vars.yaml exists.
		if [ -f "$1/docs/templating_vars.yaml" ]; then
			yq -i "(.versions.[] | select(. == \"*dev\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"
			yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" "$1/docs/templating_vars.yaml"
			yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" "$1/docs/templating_vars.yaml"
		fi

		#--------------------------------------------------------------------------
		# Replace "nightly" link so the documentation refers to the current version
		#--------------------------------------------------------------------------
		for file in $(find "$1/docs" -name "*.adoc"); do
			sed -i "s/nightly@home/home/g" "$file"
		done
	else
		echo "No docs found under $1."
	fi

	# Update operator version for the integration tests
	# this is used when installing the operators.
	yq -i ".releases.tests.products[].operatorVersion |= sub(\"0.0.0-dev\", \"${RELEASE_TAG}\")" "$1/tests/release.yaml"
}

push_branch() {
	if $PUSH; then
		echo "Pushing changes..."
		git push "${REPOSITORY}" "${RELEASE_BRANCH}"
		git push "${REPOSITORY}" "${RELEASE_TAG}"
		git switch main
	else
		echo "(Dry-run: not pushing...)"
	fi
}

cleanup() {
	if $CLEANUP; then
		echo "Cleaning up..."
		rm -rf "$TEMP_RELEASE_FOLDER"
	fi
}

update_changelog() {
	TODAY=$(date +'%Y-%m-%d')
	sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_TAG] - $TODAY/I" "$1"/CHANGELOG.md
}

update_product_images_changelogs() {
	TODAY=$(date +'%Y-%m-%d')
	sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_TAG] - $TODAY/I" ./CHANGELOG.md
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
			echo "Unknown parameter passed: $1"
			exit 1
			;;
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
	RELEASE="$(cut -d'.' -f1,2 <<<"$RELEASE_TAG")"
	RELEASE_BRANCH="release-$RELEASE"

	INITIAL_DIR="$PWD"
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
	TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

	echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
	parse_inputs "$@"
	#-----------------------------------------------------------
	# check if tag argument provided
	#-----------------------------------------------------------
	if [ -z "${RELEASE_TAG}" ]; then
		echo "Usage: create-release-tag.sh -t <tag> [-p] [-c] [-w both|products|operators]"
		exit 1
	fi
	#-----------------------------------------------------------
	# check if argument matches our tag regex
	#-----------------------------------------------------------
	if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
		echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
		exit 1
	fi

	# sanity checks before we start: folder, branches etc.
	# deactivate -e so that piped commands can be used
	set +e
	checks
	set -e

	echo "Cloning docker images and operators to [$TEMP_RELEASE_FOLDER]"
	tag_repos
	cleanup
}

main "$@"
