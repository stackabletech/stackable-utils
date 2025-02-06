#!/usr/bin/env bash
#
# Description
#
# This scripts generates the OLM manifests required to install an operator from a custom catalog.
# These are not required to install an operator from the OperatorHub.
#
# The images are published under oci.stackable.tech/sandbox since they are only needed during development.
#
# This script makes the following *assumptions*:
#
# - There is a clone of the openshift-certified-operators repository in the folder passed as -c argument.
#   This is the same as the build-manifests.sh script.
#   Ensure the openshift-certified-operators repo is located on the correct branch (this is not supplied as an arguments).
#
# - The operator manifests for the given version have been generated with the build-manifests.sh script
#   and are available in that repository under operators/<operator>/version/manifests.
#
# - If a deployment is also done (with -d) then the namespace called "stackable-operators" is available.
#
# Usage
#
#   ./olm/build-bundles.sh [options]
#
# Options
#
#   -c <location of the RH cert operators repo>
#   -r <release>: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
#   -o <operator-name>: the operator name (mandatory) e.g. airflow. Without the "-operator" suffix!
#   -d <deploy>: optional flag for operator deployment.
#
# Example
#
#   ./olm/build-bundles.sh \
#       -r 23.4.1 \
#       -o secret \
#       -c $HOME/repo/stackable/openshift-certified-operators \
#       -d
#

set -euo pipefail
set -x

SCRIPT_NAME=$(basename "$0")

parse_inputs() {
  VERSION=""
  OPERATOR=""
  DEPLOY=false

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -r | --release)
      VERSION="$2"
      shift
      ;;
    -c)
      OPENSHIFT_ROOT="$2"
      shift
      ;;
    -o | --operator)
      OPERATOR="$2"
      shift
      ;;
    -d | --deploy) DEPLOY=true ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
    esac
    shift
  done
}

bundle-clean() {
  rm -rf "bundle"
  rm -rf "bundle.Dockerfile"
}

build-bundle() {
  opm alpha bundle generate --directory manifests --package "${OPERATOR}-package" --output-dir bundle --channels "stable,$CHANNEL" --default "$CHANNEL"
  cp metadata/*.yaml bundle/metadata/
  docker build -t "oci.stackable.tech/sandbox/${OPERATOR}-bundle:${VERSION}" -f bundle.Dockerfile .
  docker push "oci.stackable.tech/sandbox/${OPERATOR}-bundle:${VERSION}"
  opm alpha bundle validate --tag "oci.stackable.tech/sandbox/${OPERATOR}-bundle:${VERSION}" --image-builder docker

  echo "Bundle built successfully!"
}

catalog-clean() {
  if [ -d "catalog" ]; then
    rm -rf catalog
  fi

  rm -f catalog.Dockerfile
  rm -f catalog-source.yaml
  rm -f subscription.yaml
  rm -f operator-group.yaml
}

catalog() {
  mkdir -p catalog

  opm generate dockerfile catalog

  echo "Initiating package: ${OPERATOR}"
  opm init "stackable-${OPERATOR}-operator" \
    --default-channel="$CHANNEL" \
    --output yaml >"catalog/stackable-${OPERATOR}-operator.yaml"
  ##--description="TODO: add description here" \

  echo "Add operator to package: ${OPERATOR}"
  {
    echo "---"
    echo "schema: olm.channel"
    echo "package: stackable-${OPERATOR}-operator"
    echo "name: \"$CHANNEL\""
    echo "entries:"
    echo "- name: ${OPERATOR}-operator.v${VERSION}"
    echo "---"
    echo "schema: olm.channel"
    echo "package: stackable-${OPERATOR}-operator"
    echo "name: stable"
    echo "entries:"
    echo "- name: ${OPERATOR}-operator.v${VERSION}"

  } >>"catalog/stackable-${OPERATOR}-operator.yaml"
  echo "Render operator: ${OPERATOR}"
  opm render "oci.stackable.tech/sandbox/${OPERATOR}-bundle:${VERSION}" --output=yaml >>"catalog/stackable-${OPERATOR}-operator.yaml"

  echo "Validating catalog..."
  opm validate catalog

  echo "Build and push catalog for all ${OPERATOR} operator..."
  docker build . -f catalog.Dockerfile -t "oci.stackable.tech/sandbox/stackable-${OPERATOR}-catalog:latest"
  docker push "oci.stackable.tech/sandbox/stackable-${OPERATOR}-catalog:latest"

  echo "Generating catalog source..."
  cat >catalog-source.yaml <<CATALOGSOURCE
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: stackable-${OPERATOR}-catalog
spec:
  sourceType: grpc
  image: oci.stackable.tech/sandbox/stackable-${OPERATOR}-catalog:latest
  displayName: Stackable Catalog
  publisher: Stackable GmbH
  updateStrategy:
    registryPoll:
      interval: 10m
  grpcPodConfig:
    tolerations:
    - key: keep-out
      value: "yes"
      operator: Equal
      effect: NoSchedule
CATALOGSOURCE

  echo "Generating subscription ..."
  cat >subscription.yaml <<SUBSCRIPTION
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: stackable-${OPERATOR}-subscription
spec:
  channel: '$CHANNEL'
  name: stackable-${OPERATOR}-operator # this is the package name NOT the operator-name
  source: stackable-${OPERATOR}-catalog
  sourceNamespace: stackable-operators
  startingCSV: ${OPERATOR}-operator.v${VERSION}
  config:
    tolerations:
    - key: keep-out
      value: "yes"
      operator: Equal
      effect: NoSchedule
    env:
    - name: SOME_IMPORTANT_FEATURE_FLAG
      value: "turn-it-on"
SUBSCRIPTION

  echo "Generating operator group ..."
  cat >operator-group.yaml <<OPERATORGROUP
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: stackable-operator-group
spec:
  upgradeStrategy: Default

OPERATORGROUP

  echo "Catalog, operator group and subscription built (but not deployed) successfully!"
}

deploy() {
  if $DEPLOY; then
    kubectl describe namespace stackable-operators || kubectl create namespace stackable-operators
    kubectl apply --namespace stackable-operators \
      -f catalog-source.yaml \
      -f subscription.yaml \
      -f operator-group.yaml
    echo "Operator deployment done!"
  else
    echo "Skip operator deployment!"
  fi
}

main() {
  parse_inputs "$@"
  if [ -z "${VERSION}" ] || [ -z "${OPENSHIFT_ROOT}" ] || [ -z "${OPERATOR}" ]; then
    echo "Usage: $SCRIPT_NAME -r <release> -o <operator> -c <path-to-openshift-repo>"
    exit 1
  fi

  CHANNEL="$(echo "$VERSION" | sed 's/\.[^.]*$//')"

  if [ "$OPERATOR" == "spark-k8s" ]; then
    echo "Renaming operator from spark-k8s to spark"
    OPERATOR="spark"
  fi

  # this is the same folder that is also used by build-manifests.sh
  cd "${OPENSHIFT_ROOT}/operators/stackable-${OPERATOR}-operator/${VERSION}"

  # clean up any residual files from previous actions
  bundle-clean
  build-bundle

  catalog-clean
  catalog

  deploy
}

main "$@"
