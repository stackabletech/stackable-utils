# Release tools

## Install requirements

### Python 3

A working python 3 installation is required by the cargo-version.py script.

Install required packages:

    pip install -r release/requirements.txt

### Optional: GitHub CLI

Optionally, if you want to have a GitHub Pull-Request automatically created, you need the GitHib command line tools installed and properly configured. See https://cli.github.com/.

## Usage

To make a release pull-request, go to the folder containing a Cargo workspace or crate and run:

    release.sh release

To bump the version and create pull-request:

    release.sh [<next-devel-level>]

where `next-devel-level` is the version level to be bumped. This ca be `major`, `minor` or `patch`.

This pushes two commits in a newly created release branch.

Examples:

    # Perform release
    $ release.sh release

    # Bump the minor version but do not push anything to origin
    $ release.sh minor false

    # Bump the major version, push and make a pull-request
    $ release.sh major

## Description

The release process performs the following steps:
0. Create a release branch from `main`.
1. Update the release version in the cargo workspace by dropping the "-nightly" token.
2. Update `Cargo.lock` with the new version.
3. Regenerate Helm chart and manifests.
4. Update the CHANGELOG.md entry of this release
5. Commit, tag and push the changes.
6. __Optional__: if the GitHub cli is installed, a PR is created.

Raising the next development version includes the following steps:
0. Create a release branch from `main`.
1. Set the version to the next development version by increasing the 'next-devel-level' (by default) part and adding the '-nightly' prerelease token.
2. Update `Cargo.lock` with the new version.
3. Regenerate Helm chart and manifests.
4. Commit and push
5. __Optional__: if the GitHub cli is installed, a PR is created.
