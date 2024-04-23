#
# Build bundle manifests and index images
#
# An experimental script that builds a custom operator catalog containing two
# versions of the same operator.
#
# Assumes the bundle images are built and pushed to a registry as follows:
#
#./olm/build-manifests.py --openshift-versions v4.11-v4.15 --release 23.11.0 --repo-operator /home/razvan/repo/stackable/airflow-operator --replaces 23.4.1
#./olm/build-manifests.py --openshift-versions v4.11-v4.15 --release 24.3.0 --repo-operator /home/razvan/repo/stackable/airflow-operator --replaces 23.11.0
#
# See: https://olm.operatorframework.io/docs/reference/catalog-templates/#example
# for an example catalog with multiple bundles
#
export OPERATOR=airflow

mkdir -p olm/catalog
opm generate dockerfile olm/catalog

opm init "stackable-${OPERATOR}-operator" \
	--default-channel=stable \
	--output yaml >"olm/catalog/stackable-${OPERATOR}-operator.yaml"

echo "Add operator to package: ${OPERATOR}"
{
	echo "---"
	echo "schema: olm.channel"
	echo "package: stackable-${OPERATOR}-operator"
	echo "name: stable"
	echo "entries:"
	echo "- name: ${OPERATOR}-operator.v24.3.0"
	echo "- name: ${OPERATOR}-operator.v23.11.0"
} >>"olm/catalog/stackable-${OPERATOR}-operator.yaml"
echo "Render operator: ${OPERATOR}"
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:23.11.0" --output=yaml >>"olm/catalog/stackable-${OPERATOR}.v23.11.0-bundle.yaml"
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:24.3.0" --output=yaml >>"olm/catalog/stackable-${OPERATOR}-v24.30-bundle.yaml"
echo "- name: ${OPERATOR}-operator.v23.11.0"
replaces: airflow-operator.v23.11.0

echo "Validating catalog..."
opm validate olm/catalog

echo "Build catalog..."
docker build olm -f olm/catalog.Dockerfile -t "docker.stackable.tech/sandbox/stackable-${OPERATOR}-catalog:multi"
docker push "docker.stackable.tech/sandbox/stackable-${OPERATOR}-catalog:multi"

export VERSION="multi"

echo "Generating catalog source..."
{
	echo "---"
	echo "apiVersion: operators.coreos.com/v1alpha1"
	echo "kind: CatalogSource"
	echo "metadata:"
	echo "  name: stackable-${OPERATOR}-catalog"
	echo "spec:"
	echo "  sourceType: grpc"
	echo "  image: docker.stackable.tech/sandbox/stackable-${OPERATOR}-catalog:${VERSION}"
	echo "  displayName: Stackable Catalog"
	echo "  publisher: Stackable GmbH"
	echo "  updateStrategy:"
	echo "    registryPoll:"
	echo "      interval: 10m"
} >catalog-source.yaml

echo "Generating subscription ..."
{
	echo "---"
	echo "apiVersion: operators.coreos.com/v1alpha1"
	echo "kind: Subscription"
	echo "metadata:"
	echo "  name: stackable-${OPERATOR}-subscription"
	echo "spec:"
	echo "  channel: stable"
	echo "  name: stackable-${OPERATOR}-operator" # this is the package name NOT the operator-name
	echo "  source: stackable-${OPERATOR}-catalog"
	echo "  sourceNamespace: stackable-operators"
	echo "  startingCSV: ${OPERATOR}-operator.v${VERSION}"
} >subscription.yaml

echo "Generating operator group ..."
{
	echo "---"
	echo "apiVersion: operators.coreos.com/v1"
	echo "kind: OperatorGroup"
	echo "metadata:"
	echo "  name: stackable-operator-group"
	echo "spec:"
	echo "  targetNamespaces:"
	echo "  - stackable-operators"
} >operator-group.yaml
