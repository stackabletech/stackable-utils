# Renovate

This directory contains tools necessary to run Renovate manually against our repositories.

For reasons unknown to us this currently (2023-07) does not work from within Jenkins, which is why we run it manually.
I am not sure if we have tried to move it into a GitHub Action, which would be one reasonable thing to try.
                      
You need an access token for GitHub for the Stacky McStackface user.
The script assumes an environment variable named `GITHUB_TOKEN` exists.

Then just run `run_renovate.sh`.
The script `list_repos.sh` will return a list of all non-archived, non-fork repositories for Stackable.
