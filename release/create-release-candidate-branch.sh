#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
# set -x

# tags should be semver-compatible e.g. 23.1.1 not 23.01.1
# this is needed for cargo commands to work properly
# optional release-candidate suffixes are in the form:
#	- rc-1, e.g. 23.1.1-rc1, 23.12.1-rc12 etc.
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+(-rc[0-9]+)?$"
REMOTE="origin"
PR_MSG="> [!CAUTION]
> ## DO NOT MERGE MANUALLY!
> This branch will be merged (and the commit tagged) by stackable-utils once any necessary commits have been cherry-picked to here from the main branch."

rc_branch_products() {
	# assume that the branch exists and has either been pushed or has been created locally
	cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

	# the PR branch should already exist
	git switch "$PR_BRANCH"
	update_product_images_changelogs

	git commit -sam "chore: Release $RELEASE_TAG"
	push_branch
}

rc_branch_operators() {
	while IFS="" read -r operator || [ -n "$operator" ]; do
		cd "${TEMP_RELEASE_FOLDER}/${operator}"
		git switch "$PR_BRANCH"

		# Update git submodules if needed
		if [ -f .gitmodules ]; then
			git submodule update --recursive --init
		fi

		# set tag version where relevant
		cargo set-version --offline --workspace "$RELEASE_TAG"
		cargo update --workspace
		# Run via nix-shell for the correct dependencies. Makefile already calls
		# nix stuff, so it shouldn't be a problem for non-nix users.
		nix-shell --run 'make regenerate-charts'
		nix-shell --run 'make regenerate-nix'

		update_code "$TEMP_RELEASE_FOLDER/${operator}"

		# ensure .j2 changes are resolved
		"$TEMP_RELEASE_FOLDER/${operator}"/scripts/docs_templating.sh

		# inserts a single line with tag and date
		update_changelog "$TEMP_RELEASE_FOLDER/${operator}"

		git commit -sam "chore: Release $RELEASE_TAG"
		push_branch
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

rc_branch_repos() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		rc_branch_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		rc_branch_operators
	fi
}

check_tag_is_valid() {
	git fetch --tags

	# check tags: N.B. look for exact match
	if git tag --list | grep -E "^$RELEASE_TAG\$"; then
		>&2 echo "Tag $RELEASE_TAG already exists!"
		exit 1
	fi

	# Do we want proper semver version checking?
	# We should switch this script to python if so.
	#EXISTING_TAGS=$(git tag --list | grep -E "$RELEASE" | sort -V)
	#for EXISTING_TAG in $EXISTING_TAGS; do
	#	if [[ "$RELEASE_TAG" < "$EXISTING_TAG" ]]; then
	#		>&2 echo "Error: Proposed tag $RELEASE_TAG is earlier than existing tag $EXISTING_TAG."
	#		exit 1
	#	fi
	#done
}

check_products() {
	echo "Checking products"

	if [ ! -d "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO" ]; then
		echo "Cloning folder: $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  		# $TEMP_RELEASE_FOLDER has already been created in main()
  		git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
	fi
	cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

	# switch to the release branch, which should exist as tagging
	# is subsequent to creating the branch.
	# Note, if this needs to check the branch exists locally, then use:
	# "^[ *]*$RELEASE_BRANCH\$"
	if ! git branch -a | grep -E "$RELEASE_BRANCH\$"; then
		>&2 echo "Expected release branch is missing: $RELEASE_BRANCH"
		exit 1
	fi

	# the new PR should not exist, otherwise a duplicate commit
	# will be prepared
	# Note, if this needs to check the branch exists locally, then use:
	# "^[ *]*$PR_BRANCH\$"
	if git branch -a | grep -E "$PR_BRANCH\$"; then
		>&2 echo "PR branch already exists: ${REMOTE}/$PR_BRANCH"
		exit 1
	fi

	# create a new branch for the PR off of this
	git switch -c "$PR_BRANCH" "$RELEASE_BRANCH"

	check_tag_is_valid
}

check_operators() {
	echo "Checking operators"

	while IFS="" read -r operator || [ -n "$operator" ]; do
		echo "Operator: $operator"
		if [ ! -d "$TEMP_RELEASE_FOLDER/${operator}" ]; then
			echo "Cloning folder: $TEMP_RELEASE_FOLDER/${operator}"
			# $TEMP_RELEASE_FOLDER has already been created in main()
			git clone "git@github.com:stackabletech/${operator}.git" "$TEMP_RELEASE_FOLDER/${operator}"

		fi
		cd "$TEMP_RELEASE_FOLDER/${operator}"
		# Note, if this needs to check the branch exists locally, then use:
		# "^[ *]*$RELEASE_BRANCH\$"
		if ! git branch -a | grep -E "$RELEASE_BRANCH\$"; then
			>&2 echo "Expected release branch is missing: ${operator}/$RELEASE_BRANCH"
			exit 1
		fi

		# the new PR should not exist, otherwise a duplicate commit
		# will be prepared
		# Note, if this needs to check the branch exists locally, then use:
		# "^[ *]*$PR_BRANCH\$"
		if git branch -a | grep -E "$PR_BRANCH\$"; then
			>&2 echo "PR branch already exists: ${operator}/$PR_BRANCH"
			exit 1
		fi

		# create a new branch for the PR off of this
		git switch -c "$PR_BRANCH" "$RELEASE_BRANCH"

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

update_code() {
	if [ -d "$1/docs" ]; then
		echo "Updating antora docs for $1"

		# antora version should be major.minor, not patch level
		yq -i ".version = \"${RELEASE}\"" "$1/docs/antora.yml"
		yq -i '.prerelease = false' "$1/docs/antora.yml"

		# Not all operators have a getting started guide
		# that's why we verify if templating_vars.yaml exists.
		if [ -f "$1/docs/templating_vars.yaml" ]; then

			# for an initial tag for a given release...
			yq -i "(.versions.[] | select(. == \"*dev\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"

			# ...consider for patch releases/release candidates too
			# We assume that the tag (e.g. 23.7.1) is applied to an earlier tag in the same
			# release (e.g. 23.7.0) so search+replace on the major.minor tag will suffice.
			# TODO: this may pick up versions of external components as well.
			yq -i "(.versions.[] | select(. == \"${RELEASE}*\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"

			yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" "$1/docs/templating_vars.yaml"
			yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" "$1/docs/templating_vars.yaml"
		fi

		# Replace "nightly" link so the documentation refers to the current version
		for file in $(find "$1/docs" -name "*.adoc"); do
			sed -i "s/nightly@home/home/g" "$file"
		done
	else
		echo "No docs found under $1."
	fi

	# Update operator version for the integration tests
	# (used when installing the operators).
	yq -i ".releases.tests.products[].operatorVersion |= sub(\"0.0.0-dev\", \"${RELEASE_TAG}\")" "$1/tests/release.yaml"

	# do this for patch releases/release candidates too.
	# i.e. replace 24.11.0-rc1 with 24.11.0, 24.7.0 with 24.7.1 etc.
	yq -i "(.releases.tests.products[].operatorVersion | select(. == \"${RELEASE}*\")) |= \"${RELEASE_TAG}\"" "$1/tests/release.yaml"

	# Some tests perform **label** inspection and for (only) these cases specific labels should be updated.
	# N.B. don't do this for all test files as not all images will necessarily exist for the given release tag.
	find "$1/tests/templates/kuttl" -type f -print0 | xargs -0 sed -E -i "s#(app\.kubernetes\.io/version: \".*-stackable)[^\"]*#\1$RELEASE_TAG#"
}

push_branch() {
	if $PUSH; then
		echo "Pushing changes..."
		# the branch must be updated before the PR can be created
		git push -u "$REMOTE" "$PR_BRANCH"
		gh pr create --reviewer stackabletech/developers --base "${RELEASE_BRANCH}" --head "${PR_BRANCH}" --title "chore: Release ${RELEASE_TAG}" --body "${PR_MSG}"
	else
		echo "Dry-run: not pushing changes..."
		git push --dry-run -u "$REMOTE" "$PR_BRANCH"
		gh pr create --reviewer stackabletech/developers --dry-run --base "${RELEASE_BRANCH}" --head "${PR_BRANCH}" --title "chore: Release ${RELEASE_TAG}" --body "${PR_MSG}"
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
	# N.B. this has to match what is used in other scripts
	PR_BRANCH="pr-$RELEASE_TAG"

	INITIAL_DIR="$PWD"
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
	TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

	echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

check_dependencies() {
	# check for a globally configured git user
	if ! git_user=$(git config --global --includes --get user.name) \
	|| ! git_email=$(git config --global --includes --get user.email); then
		>&2 echo "Error: global git user name/email is not set."
		exit 1
	else
		echo "global git user: $git_user <$git_email>"
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
	  	echo "Creating folder for cloning docker images and/or operators: [$TEMP_RELEASE_FOLDER]"
  		mkdir -p "$TEMP_RELEASE_FOLDER"
	fi

	check_dependencies

	# sanity checks before we start: folder, branches etc.
	checks

	echo "Cloning docker-images and/or operators to [$TEMP_RELEASE_FOLDER]"
	rc_branch_repos
	cleanup
}

main "$@"
