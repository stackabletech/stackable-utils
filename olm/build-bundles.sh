#!/usr/bin/env bash
# This script does the following:
#   - clones
# Usage:
#   ./olm/build-bundles.sh -r <release as x.y.z> -b <branch-name>
#   -r <release>: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
#   -b <branch>: the branch name (mandatory) in the (stackable forked) openshift-certified-operators repository.
#   -o <operator-name>: the operator name (mandatory) e.g. airflow-operator.
#   -d <deploy>: optional flag for catalog deployment.
#
# e.g. ./olm/build-bundles.sh -r 23.4.1 -b secret-23.4.1 -o secret-operator -d

set -euo pipefail
set -x


SCRIPT_NAME=$(basename $0)

parse_inputs() {
  INITIAL_DIR="$PWD"

  VERSION=""
  BRANCH=""
  OPERATOR_NAME=""
  DEPLOY=false

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -r|--release) VERSION="$2"; shift ;;
          -b|--branch) BRANCH="$2"; shift ;;
          -o|--operator) OPERATOR_NAME="$2"; shift ;;
          -d|--deploy) DEPLOY=true ;;
          *) echo "Unknown parameter passed: $1"; exit 1 ;;
      esac
      shift
  done

  # e.g. "airflow" instead of "airflow-operator"
  OPERATOR=$(echo "${OPERATOR_NAME}" | cut -d- -f1)
}

bundle-clean() {
	rm -rf "bundle"
	rm -rf "bundle.Dockerfile"
}

build-bundle() {
	opm alpha bundle generate --directory manifests --package "${OPERATOR_NAME}-package" --output-dir bundle --channels stable --default stable
  cp metadata/*.yaml bundle/metadata/
  docker build -t "docker.stackable.tech/stackable/${OPERATOR_NAME}-bundle:${VERSION}" -f bundle.Dockerfile .
  docker push "docker.stackable.tech/stackable/${OPERATOR_NAME}-bundle:${VERSION}"
  opm alpha bundle validate --tag "docker.stackable.tech/stackable/${OPERATOR_NAME}-bundle:${VERSION}" --image-builder docker
}

setup() {
  if [ -d "catalog" ]; then
    rm -rf catalog
  fi

  mkdir -p catalog
  rm -f catalog.Dockerfile
  rm -f catalog-source.yaml
}

catalog() {
  opm generate dockerfile catalog

  echo "Initiating package: ${OPERATOR}"
  opm init "stackable-${OPERATOR}-operator" \
      --default-channel=stable \
      --description=./README.md \
      --output yaml > "catalog/stackable-${OPERATOR}-operator.yaml"
  echo "Add operator to package: ${OPERATOR}"
  {
    echo "---"
    echo "schema: olm.channel"
    echo "package: stackable-${OPERATOR}-operator"
    echo "name: stable"
    echo "entries:"
    echo "- name: ${OPERATOR}-operator.v${VERSION}"
  } >> "catalog/stackable-${OPERATOR}-operator.yaml"
  echo "Render operator: ${OPERATOR}"
  opm render "docker.stackable.tech/stackable/${OPERATOR}-operator-bundle:${VERSION}" --output=yaml >> "catalog/stackable-${OPERATOR}-operator.yaml"

  echo "Validating catalog..."
  opm validate catalog

  echo "Build and push catalog for all ${OPERATOR} operator..."
  docker build . -f catalog.Dockerfile -t "docker.stackable.tech/stackable/stackable-${OPERATOR}-catalog:${VERSION}"
  docker push "docker.stackable.tech/stackable/stackable-${OPERATOR}-catalog:${VERSION}"
}

deploy() {
  if $DEPLOY; then
    echo "Deploying catalog..."

    {
    echo "---"
    echo "apiVersion: operators.coreos.com/v1alpha1"
    echo "kind: CatalogSource"
    echo "metadata:"
    echo "  name: stackable-${OPERATOR}-catalog"
    echo "  namespace: stackable-operators"
    echo "spec:"
    echo "  sourceType: grpc"
    echo "  image: docker.stackable.tech/stackable/stackable-${OPERATOR}-catalog:${VERSION}"
    echo "  displayName: Stackable Catalog"
    echo "  publisher: Stackable GmbH"
    echo "  updateStrategy:"
    echo "    registryPoll:"
    echo "      interval: 10m"
    } >> catalog-source.yaml

    kubectl apply -f catalog-source.yaml
    echo "Catalog deployment successful!"
  fi
}

main() {
  parse_inputs "$@"
  if [ -z "${VERSION}" ] || [ -z "${BRANCH}" ] || [ -z "${OPERATOR_NAME}" ]; then
    echo "Usage: $SCRIPT_NAME -r <release> -b <branch> -o <operator>"
    exit 1
  fi

  TMPFOLDER=$(mktemp -d -t 'openshift-bundles-XXXXXXXX')
  cd "${TMPFOLDER}"

  git clone "git@github.com:stackabletech/openshift-certified-operators.git" --depth 1 --branch "${BRANCH}" --single-branch "${TMPFOLDER}/openshift-certified-operators/"

  cd "${TMPFOLDER}/openshift-certified-operators/operators/stackable-${OPERATOR}-operator/${VERSION}"

  # clean up any residual files from previous actions
  bundle-clean
  build-bundle

  # should not be pushed to repo (unintentionally) once bundle is built, so clean up straight away
  bundle-clean

  echo "Bundle-build successful!"

  pushd "$INITIAL_DIR/olm"
  setup
  catalog
  deploy

  popd
  echo "Catalog built successfully!"
}

main "$@"
