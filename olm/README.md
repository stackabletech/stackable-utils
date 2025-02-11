# Overview

This is a short guide on how to build and test OLM manifests for the Stackable operators.

The workflow contains these steps:

1. Generate OLM Manifests
2. Build and Install Bundles
3. Test Operators

# Prerequisites

- An [OpenShift](https://developers.redhat.com/products/openshift-local/overview) or an [OKD](https://okd.io/) cluster
- [operator-sdk](https://github.com/operator-framework/operator-sdk/)
- [docker](https://docs.docker.com/engine/install/)
- [kubectl](https://github.com/kubernetes/kubectl)

# Generate OLM Manifests

Before generating OLM manifests for an operator ensure that you have checked out the correct branch or tag
in the corresponding operator repository.

The OLM manifests are usually generated into the [OpenShift Certified Operators Repository](https://github.com/stackabletech/openshift-certified-operators)
which is the source of the certification process.

## Secret and Listener Operators

The manifest generation for these two operators is only partially automated.
You start with the script below and then manually update the cluster service version.
To generate the manifests for the secret operator version 24.11.1, run:

```bash
./olm/build-manifests.sh -r 24.11.1 \
  -c $HOME/repo/stackable/openshift-certified-operators \
  -o $HOME/repo/stackable/secret-operator
```

Where:
- `-r <release>`: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
- `-c <manifest folder>`: the output folder for the manifest files
- `-o <operator-dir>`: directory of the operator repository

Similarly for the listener operator run:

```bash
./olm/build-manifests.sh -r 24.11.1 \
  -c $HOME/repo/stackable/openshift-certified-operators \
  -o $HOME/repo/stackable/listener-operator
```

## All Other Operators

```bash
./olm/build-manifests.py \
  --openshift-versions 'v4.14-v4.16' \
  --release 24.11.1 \
  --skips 24.7.0 \
  --repo-operator ~/repo/stackable/hbase-operator
```

See `./olm/build-manifests.py --help` for the description of command line arguments.

# Build and Install Bundles

Operator bundles are needed to test the OLM manifests but *not needed* for the operator certification.

## Build bundles

To build operator bundles run:

```bash
./olm/build-bundles.sh \
  -c $HOME/repo/stackable/openshift-certified-operators \
  -r 24.11.1 \
  -o listener \
  -d
```

Where:
- `-r <release>`: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
- `-c <manifest folder>`: the folder with the input OLM manifests for the bundle
- `-o <operator-name>`: the operator name (mandatory) e.g. "airflow"
- `-d`: Optional. Deploy the bundle. Default: false.
N.B. This action will push the bundles to `oci.stackable.tech` and requires that the user be logged in first. This can be done by copying the CLI token from the Harbor UI once you are logged in there (see under "Profile"), and then using is as the password when prompted on entering `docker login oci.stackabe.tech`.
## Operator upgrades

To test operator upgrades run `operator-sdk run bundle-upgrade` like this:

```bash
operator-sdk run bundle-upgrade \
  oci.stackable.tech/sandbox/listener-bundle:24.11.2 \
  --namespace stackable-operators
```

# Test Operators

To run the integration tests against an operator installation (ex. listener):

```bash
./scripts/run-tests --skip-operator listener --test-suite openshift
```

Here we skip the installation of the listener operator by the test suite because this is already installed
as an operator bundle.

## Bundle cleanup

To remove an operator bundle and all associated objects, run:

```bash
operator-sdk cleanup listener-operator --namespace stackable-operators
```
