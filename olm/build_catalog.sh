#!/usr/bin/env bash

set -euo pipefail
set -x

main() {
  VERSION="$1";

  pushd olm
  echo "Deploy custom scc..."
  kubectl apply -f scc.yaml

  if [ -d "catalog" ]; then
    rm -rf catalog
  fi
  if [ -d "subscriptions" ]; then
    rm -rf subscriptions
  fi

  # catalog (just creates dockerfile with copy command)
  mkdir -p catalog
  mkdir -p subscriptions
  rm -f catalog.Dockerfile
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

  # install catalog/group for all operators
  #kubectl apply -f catalog-source.yaml
  #kubectl apply -f operator-group.yaml

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
    # kubectl apply -f "subscriptions/$operator-subscription.yaml"
  done < <(yq '... comments="" | .operators[] ' config.yaml)

  popd
  echo "Deployment successful!"
}

main "$@"
