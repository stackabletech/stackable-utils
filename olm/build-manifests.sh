#!/usr/bin/env bash

set -euo pipefail
set -x

# where the certified opreators repo is cloned
OPENSHIFT_ROOT="$HOME/repo/stackable/openshift-certified-operators"

RELEASE_VERSION="23.11.0"

# updated for each operator
PRODUCT="zookeeper"
OPERATOR="$PRODUCT-operator"
OP_ROOT="$HOME/repo/stackable/$OPERATOR"

MANIFESTS_DIR="$OPENSHIFT_ROOT/operators/stackable-$OPERATOR/$RELEASE_VERSION/manifests"

main() {

	rm -r -f "$MANIFESTS_DIR"
	mkdir -p "$MANIFESTS_DIR"

	pushd "$MANIFESTS_DIR"

	# split crd
	cat "$OP_ROOT/deploy/helm/$OPERATOR/crds/crds.yaml" | yq -s '.spec.names.kind'

	# generate configmap for product config
	kubectl create configmap "$OPERATOR-configmap" --from-file=$OP_ROOT/deploy/config-spec/properties.yaml --dry-run=client -o yaml >configmap.yaml
	yq -i ".metadata.labels.\"app.kubernetes.io/name\" = \"$OPERATOR\"" configmap.yaml
	yq -i ".metadata.labels.\"app.kubernetes.io/instance\" = \"$OPERATOR\"" configmap.yaml
	yq -i ".metadata.labels.\"app.kubernetes.io/version\" = \"$RELEASE_VERSION\"" configmap.yaml

	# expand helm templates to a temp folder
	HELM_TEMPLATE_DIR=$(mktemp -d -t "helm-$OPERATOR-XXX")

	pushd "$HELM_TEMPLATE_DIR"
	helm template "$OPERATOR" "$OP_ROOT/deploy/helm/$OPERATOR" | yq -s '.metadata.name'
	popd

	# copy role
	test -f "$HELM_TEMPLATE_DIR/$PRODUCT-clusterrole.yml" && cp "$HELM_TEMPLATE_DIR/$PRODUCT-clusterrole.yml" "$PRODUCT-clusterrole.yaml"

	popd
}

main "$@"
