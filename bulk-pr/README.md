# PR Bulk Tools

This contains a selection of scripts that can be used to bulk manipulate similar PRs across a defined set of repositories.
The requirement for PRs to be considered _similar_ for the purpose of these scripts is that the branch they are created from have the same name.

**WARNING:** 
These scripts do not contain much in the way of safety checks or security confirmations.
You are expected to know what you are doing and should most probably conduct due diligence directly on the PRs before using these tools to approve them.

## Overview
This section will give a brief overview of the tools contained in this repo.

The recommended workflow for PRs created by the operator templating is:

1. Run `pr_diff` and check for any unexpected changes
2. Periodically run `pr_status` until all PRs show 0
3. Run `pr_approve`

### Common parameters
With the only exception of the `repos` script all scripts in this repository take the same parameter, which is the name of the branch the PRs you want to operate on was created from.

For example for a set of operator templating pull requests this will usually be in the form of `template_abd68ad` which is the fixed prefix `template_` followed by the short commit hash of the commit in the operator templating repo that it was based on.

### Configuration
Configuration of all these tools is done in the `repos` script. 
This script doesn't take any parameters.
It is sourced by all the other scripts and defines the list of operator repositories that should be included in bulk operations.

Edit this file if you want to exclude operators from bulk operations for some reason, or if new operators have been created that should be included.

## Scripts
### pr_approve
Approves all pull requests and adds a `bors r+` comment to start the bors merge process.

### pr_checks
Shows all checks for all PRs and their current status. 

Checks are shown per PR, hitting `q` switches to the next PR, Ctrl-C can be used to abort the entire script.

### pr_close
Closes all PRs.

### pr_diffs
Shows the diffs for all PRs, this can be useful to double check that no unexpected changes were queued in any repository by accident.

Diffs are shown per PR, hitting `q` switches to the next PR, Ctrl-C can be used to abort the entire script.

### pr_status
Shows an abbreviated status of all PRs.

The displayed status per PR can have the following values:

| Status | Meaning                                        | 
|--------|------------------------------------------------|
| 0      | All checks were finished and successful        | 
| 1      | One or more checks failed or are still running | 
