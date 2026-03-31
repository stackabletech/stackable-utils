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

Use the `scripts/generate-olm.py` script in each operator repository (secret and listener) like this:

```shell
# Adapt path as necessary
cd $HOME/repo/openshift/openshift-certified-operators/operators/stackable-secret-operator

./scripts/generate-olm.py \
--output-dir $HOME/repo/openshift/openshift-certified-operators/operators/stackable-secret-operator \
--version <release> \
--openshift-versions v4.18-v4.21
```

Where:

- `--version <release>`: the release number (mandatory). Example: `26.3.0`.
- `--output-dir <manifest folder>`: location of the certified operators repository.
- `--openshift-versions <ocp-version-range>`: catalogs where this bundle is published. Example: `v4.18-v4.21`.

## All Other Operators

```bash
./olm/build-manifests.py \
  --openshift-versions 'v4.18-v4.21' \
  --release 24.11.1 \
  --repo-operator ~/repo/stackable/hbase-operator
```

See `./olm/build-manifests.py --help` for the description of command line arguments.

# Build and Install Bundles

Operator bundles are needed to test the OLM manifests but _not needed_ for the operator certification.

## Build bundles

To build operator bundles run:

```bash
./olm/build-bundles.sh \
  -c $HOME/repo/stackable/openshift-certified-operators \
  -r 26.3.0 \
  -o listener \
  -d
```

Where:

- `-r <release>`: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
- `-c <manifest folder>`: the folder with the input OLM manifests for the bundle
- `-o <operator-name>`: the operator name (mandatory) e.g. "airflow"
- `-d`: Optional. Deploy the bundle. Default: false.

N.B. This action will push the bundles to `oci.stackable.tech` and requires that the user be logged in first. This can be done by copying the CLI token from the Harbor UI once you are logged in there (see under "Profile"), and then using this as the password when prompted on entering `docker login oci.stackabe.tech`.

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
