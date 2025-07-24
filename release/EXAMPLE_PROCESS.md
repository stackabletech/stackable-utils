# Release script process

## Dry run testing

It is a good idea to do a dry-run check locally, and then delete the local state.

```sh
# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Create and switch to branch: release-YY.M.
./release/create-release-branch.sh -b YY.M -w products
./release/create-release-branch.sh -b YY.M -w operators
./release/create-release-branch.sh -b YY.M -w demos

# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Fetch and switch to branch: release-YY.M.
#   NOTE: this would only work for dry run if the previous step was done on the
#         same machine and not deleted. Else the release branch won't be found.
# Create and switch to branch: pr-YY.M.X-rc1.
# Update the change log, and commit it (skip pushing).
# Raise a PR (dry-run).
./release/create-release-candidate-branch.sh -t YY.M.X-rc1 -w products
./release/create-release-candidate-branch.sh -t YY.M.X-rc1 -w operators

# Pretend the PR exists, and exit.
# This doesn't really test much.
./release/merge-release-candidate.sh -t YY.M.X-rc1 -w products
./release/merge-release-candidate.sh -t YY.M.X-rc1 -w operators

# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Fetch and switch to branch: release-YY.M.
#   NOTE: this would only work for dry run if the first step was done on the
#         same machine and not deleted. Else the release branch won't be found.
# Tag the HEAD commit (in this case it would be the same as `main` where this branch was based).
./release/tag-release-candidate.sh -t YY.M.X-rc1 -w products
./release/tag-release-candidate.sh -t YY.M.X-rc1 -w operators

# TODO: ./release/post-release.sh
```

Finally, delete the dirty state:

```sh
rm -fr /tmp/stackable-release-YY.M
```

## Actual release

### Release Candidates

This procedure would be done until a viable release-candidate can be selected.

```sh
# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Create and switch to branch: release-YY.M.
# Push the branch.
./release/create-release-branch.sh -b YY.M -w products -p
./release/create-release-branch.sh -b YY.M -w operators -p
./release/create-release-branch.sh -b YY.M -w demos -p

# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Fetch and switch to branch: release-YY.M.
# Create and switch to branch: pr-YY.M.X-rc1.
# Update the change log, and commit it.
# Push the branch.
# Raise a PR.
./release/create-release-candidate-branch.sh -t YY.M.X-rc1 -w products -p
./release/create-release-candidate-branch.sh -t YY.M.X-rc1 -w operators -p
```

Ask people to do approvals.

> [!TIP]
> It is nice to drop all the links in a Slack message to make it easier.
> You can search the output for `https://github.com/stackabletech/.*/pull/[0-9]+`

Once all approvals are done, merge the changes and tag the release branch `HEAD`.

```sh
# Check that PRs are `OPEN`.
# Merge the PR (this does not seem to wait for checks to complete).
./release/merge-release-candidate.sh -t YY.M.X-rc1 -w products -p
./release/merge-release-candidate.sh -t YY.M.X-rc1 -w operators -p
```

It is still worth checking that all PRs are merged.

```sh
# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Fetch, including tags.
# Ensure tag does not already exist.
# Switch to the release branch.
# Pull.
# Tag HEAD.
# Push tag.
./release/tag-release-candidate.sh -t YY.M.X-rc1 -w products -p
./release/tag-release-candidate.sh -t YY.M.X-rc1 -w operators -p
```

> [!CAUTION]
> Wait for images to be built.
>
> To ensure all image artifacts have been pushed, see [image-checks.sh](./image-checks.sh).

Now do release candidate Testing.

Repeat this process if this release-candidate is not viable (changing `rc1` to `rc2` for example).

### Promote RC to Release

Once the release candidate has been deemed good, do the release proper:

> [!NOTE]
> `create-release-candidate-branch` is a misnomer, since it is a release branch.
> But this step is necessary to update the version numbers throughout the repository
> to the final version number for the release.

```sh
# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Fetch and switch to branch: release-YY.M.
# Create and switch to branch: pr-YY.M.X.
# Update the change log, and commit it.
# Push the branch.
# Raise a PR.
./release/create-release-candidate-branch.sh -t YY.M.X -w products -p
./release/create-release-candidate-branch.sh -t YY.M.X -w operators -p
```

Ask people to do approvals.

> [!TIP]
> It is nice to drop all the links in a Slack message to make it easier.
> You can search the output for `https://github.com/stackabletech/.*/pull/[0-9]+`

Once all approvals are done, merge the changes and tag the release branch `HEAD`.

```sh
# Check that PRs are `OPEN`.
# Merge the PR (this does not seem to wait for checks to complete).
./release/merge-release-candidate.sh -t YY.M.X -w products -p
./release/merge-release-candidate.sh -t YY.M.X -w operators -p

# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Fetch, including tags.
# Ensure tag does not already exist.
# Switch to the release branch.
# Pull.
# Tag HEAD.
# Push tag.
./release/tag-release-candidate.sh -t YY.M.X -w products -p
./release/tag-release-candidate.sh -t YY.M.X -w operators -p
```

> [!CAUTION]
> Wait for images to be built.
>
> To ensure all image artifacts have been pushed, see [image-checks.sh](./image-checks.sh).

Once everything is looking good, the release can be mentioned in the `main` branch.

```sh
# Clone to /tmp/stackable-release-YY.M/docker-images and/or enter the directory.
# Fetch, including tags.
# Ensure the release tag exists.
# Checkout the main branch.
# Pull.
# Create and switch to branch: chore/update-changelog-from-release-YY.M.X.
# Checkout the CHANGELOG.md at tag YY.M.X.
# Ensure only the CHANGELOG.md has changed.
#   NOTE: It could be possible that new changes have gone into `main`.
#         These will need to be fixed on the branch (they should be obvious when
#         reviewing the PR).
# Add and commit the CHANGELOG.md from the release.
# Push the branch.
# Raise a PR.
./release/post-release.sh -t YY.M.X -p
```

Ask people to do approvals.

> [!TIP]
> It is nice to drop all the links in a Slack message to make it easier.
> You can search the output for `https://github.com/stackabletech/.*/pull/[0-9]+`

Once all approvals are done, manually merge the PRs.
