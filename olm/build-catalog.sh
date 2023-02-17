#!/usr/bin/env bash
# Usage:
#   ./olm/build-catalog.sh <release as x.y.z> [-n] [-d] [-s]
#   -r <release>: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
#   -n: create namespace stackable-operators (optional, default is "false").
#   -d: deploy catalog and group (optional, default is "false").
#   -s: deploy subscriptions (optional, default is "false").

set -euo pipefail
set -x


parse_inputs() {
  VERSION=""
  NAMESPACE=false
  SUBSCRIPTIONS=false
  DEPLOY=false

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -r|--release) VERSION="$2"; shift ;;
          -n|--namespace) NAMESPACE=true ;;
          -d|--deploy) DEPLOY=true ;;
          -s|--subscriptions) SUBSCRIPTIONS=true ;;
          *) echo "Unknown parameter passed: $1"; exit 1 ;;
      esac
      shift
  done
}

setup() {
  if [ -d "catalog" ]; then
    rm -rf catalog
  fi
  if [ -d "subscriptions" ]; then
    rm -rf subscriptions
  fi

  mkdir -p catalog
  mkdir -p subscriptions
  rm -f catalog.Dockerfile
  rm -f catalog-source.yaml
}

prerequisites() {
  echo "Deploy custom scc..."
  kubectl apply -f scc.yaml

  if $NAMESPACE; then
    echo "Creating namespace..."
    kubectl apply -f namespace.yaml
  fi
}

catalog() {
  opm generate dockerfile catalog

  # iterate over operators
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo "Initiating package: ${operator}"
    opm init "${operator}-operator-package" \
        --default-channel=stable \
        --description=./README.md \
        --output yaml > "catalog/${operator}-operator-package.yaml"
    echo "Add operator to package: ${operator}"
    {
      echo "---"
      echo "schema: olm.channel"
      echo "package: ${operator}-operator-package"
      echo "name: stable"
      echo "entries:"
      echo "- name: ${operator}-operator.v${VERSION}"
    } >> "catalog/${operator}-operator-package.yaml"
    echo "Render operator: ${operator}"
    opm render "docker.stackable.tech/stackable/${operator}-operator-bundle:${VERSION}" --output=yaml >> "catalog/${operator}-operator-package.yaml"
  done < <(yq '... comments="" | .operators[] ' config.yaml)

  echo "Validating catalog..."
  opm validate catalog

  echo "Build and push catalog for all operators..."
  docker build . -f catalog.Dockerfile -t "docker.stackable.tech/stackable/stackable-operators-catalog:${VERSION}"
  docker push "docker.stackable.tech/stackable/stackable-operators-catalog:${VERSION}"
}

subscriptions() {
  # iterate over operator list to deploy
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo "Deploy subscription: ${operator}"
    {
    echo "---"
    echo "apiVersion: operators.coreos.com/v1alpha1"
    echo "kind: Subscription"
    echo "metadata:"
    echo "  name: $operator-operator-subscription"
    echo "  namespace: stackable-operators"
    echo "spec:"
    echo "  channel: stable"
    echo "  name: $operator-operator-package"
    echo "  source: stackable-operators-catalog"
    echo "  sourceNamespace: stackable-operators"
    echo "  installPlanApproval: Automatic"
    } >> "subscriptions/$operator-subscription.yaml"
    if $SUBSCRIPTIONS; then
      kubectl apply -f "subscriptions/$operator-subscription.yaml"
    fi
  done < <(yq '... comments="" | .operators[] ' config.yaml)
}

deploy() {
  if $DEPLOY; then
    {
    echo "---"
    echo "apiVersion: operators.coreos.com/v1alpha1"
    echo "kind: CatalogSource"
    echo "metadata:"
    echo "  name: stackable-operators-catalog"
    echo "  namespace: stackable-operators"
    echo "spec:"
    echo "  sourceType: grpc"
    echo "  image: docker.stackable.tech/sandbox/test/stackable-operators-catalog:${VERSION}"
    echo "  displayName: Stackable Catalog"
    echo "  publisher: Stackable GmbH"
    echo "  updateStrategy:"
    echo "    registryPoll:"
    echo "      interval: 10m"
    } >> catalog-source.yaml

    kubectl apply -f catalog-source.yaml
    kubectl apply -f operator-group.yaml
  fi
}

main() {
  parse_inputs "$@"
  if [ -z "${VERSION}" ]; then
    echo "Usage: build-catalog.sh -r <release>"
    exit 1
  fi

  pushd olm

  setup
  prerequisites
  catalog
  deploy
  subscriptions

  popd
  echo "Deployment successful!"
}

main "$@"
