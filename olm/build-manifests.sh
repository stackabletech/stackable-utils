#!/usr/bin/env bash
#
# NOTE: This script is intended to be used only with the secret and listener ops.
# For all other operators, use the Python equivalent script: build-manifests.py
#
# Helper script to (re)generate OLM package manifests (skeletons).
#
# Usage:
#
#   ./olm/build-manifests.sh -r <release as x.y.z> -c <location of the RH cert operators repo> -o <location of the operator repo>
#
# Example:
#
#   ./olm/build-manifests.sh -r 23.11.0 -c $HOME/repo/stackable/openshift-certified-operators -o $HOME/repo/stackable/zookeeper-operator
#
# Before running the script:
# * Ensure the certified-operators and operator repos are located on the correct branches (the branches are not supplied as arguments).
# * Update the supported OpenShift version range in the `generate_metadata()` function.
#
# The generated manifests need to be updated manually with the following steps:
# * Copy the cluster service version file from the previous package version.
# * Replace the contents of the deployment, and cluster role with the `template.spec` and `rules` from the newly generated files.
# * Remove the unused generated files : service account, operator cluster role (not the product cluster role), role binding, deployment.
# * Remove all Helm labels in all remaining files (including all labels from the cluster role).
# * Check or update the metadata/dependencies.yaml
# * Update image tags and hashes

set -euo pipefail
set -x

# CLI args
OPENSHIFT_ROOT=""
OP_ROOT=""
RELEASE_VERSION=""

# derived from CLI args
PRODUCT=""
OPERATOR=""
MANIFESTS_DIR=""
METADATA_DIR=""

generate_metadata() {

  # generate metadata
  rm -r -f "$METADATA_DIR"
  mkdir -p "$METADATA_DIR"

  pushd "$METADATA_DIR"

  cat >annotations.yaml <<-ANNOS
---
annotations:
  operators.operatorframework.io.bundle.channel.default.v1: "${RELEASE}"
  operators.operatorframework.io.bundle.channels.v1: "${RELEASE}"
  operators.operatorframework.io.bundle.manifests.v1: manifests/
  operators.operatorframework.io.bundle.mediatype.v1: registry+v1
  operators.operatorframework.io.bundle.metadata.v1: metadata/
  operators.operatorframework.io.bundle.package.v1: stackable-${OPERATOR}

  com.redhat.openshift.versions: v4.12-v4.15
ANNOS

  cat >dependencies.yaml <<-DEPS
---
dependencies:
  - type: olm.package
    value:
      packageName: stackable-commons-operator
      version: "$RELEASE_VERSION"
  - type: olm.package
    value:
      packageName: stackable-secret-operator
      version: "$RELEASE_VERSION"
DEPS

  popd
}

generate_manifests() {
  # generate manifests
  rm -r -f "$MANIFESTS_DIR"
  mkdir -p "$MANIFESTS_DIR"

  pushd "$MANIFESTS_DIR"

  # split crd
  cat "$OP_ROOT/deploy/helm/$OPERATOR/crds/crds.yaml" | yq -s '.spec.names.kind'

  # expand config map, roles, service account, etc.
  helm template "$OPERATOR" "$OP_ROOT/deploy/helm/$OPERATOR" | yq -s '.metadata.name'

  popd
}

parse_inputs() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -r)
      RELEASE_VERSION="$2"
      RELEASE="$(cut -d'.' -f1,2 <<<"$RELEASE_VERSION")"
      shift
      ;;
    -o)
      OP_ROOT="$2"
      shift
      ;;
    -c)
      OPENSHIFT_ROOT="$2"
      shift
      ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
    esac
    shift
  done

  # e.g. "airflow" instead of "airflow-operator", "spark-k8s" instead of "spark-k8s-operator"
  PRODUCT=$(basename "${OP_ROOT}" | rev | cut -d- -f2- | rev)

  OPERATOR="$PRODUCT-operator"
  MANIFESTS_DIR="$OPENSHIFT_ROOT/operators/stackable-$OPERATOR/$RELEASE_VERSION/manifests"
  METADATA_DIR="$OPENSHIFT_ROOT/operators/stackable-$OPERATOR/$RELEASE_VERSION/metadata"
}

maybe_print_help() {
  SCRIPT_NAME=$(basename "$0")
  if [ -z "$RELEASE_VERSION" ] || [ -z "$OP_ROOT" ] || [ -z "$OPENSHIFT_ROOT" ]; then
    cat <<-HELP
          (Re)generate OLM manifest skeletons.

          Usage:

            $SCRIPT_NAME -r <release> -c <dir-to-rh-cert-op-repo> -o <dir-to-op-repo>

          Options:
            -r : Release version
            -c : Path to the RH certified operator repository
            -o : Path to the Stackable operator repository

          Example:

            $SCRIPT_NAME -r 23.11.0 -c $HOME/repo/stackable/openshift-certified-operators -o $HOME/repo/stackable/zookeeper-operator
HELP

    exit 1
  fi
}

patch_cluster_roles() {
  pushd "$MANIFESTS_DIR"

  # Add nonroot-v2 SCC to product cluster role
  if [ -f "$PRODUCT-clusterrole.yml" ]; then
    yq -i '.rules += { "apiGroups": [ "security.openshift.io" ], "resources": [ "securitycontextconstraints" ], "resourceNames": ["nonroot-v2" ], "verbs": ["use"]}' "$PRODUCT-clusterrole.yml"
  fi

  # Add nonroot-v2 SCC to operator cluster role
  if [ -f "$OPERATOR-clusterrole.yml" ]; then
    yq -i '.rules += { "apiGroups": [ "security.openshift.io" ], "resources": [ "securitycontextconstraints" ], "resourceNames": ["nonroot-v2" ], "verbs": ["use"]}' "$OPERATOR-clusterrole.yml"
  fi

  popd

}

main() {
  parse_inputs "$@"
  maybe_print_help
  generate_metadata
  generate_manifests
  patch_cluster_roles
}

main "$@"
