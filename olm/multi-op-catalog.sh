#
# Build bundle manifests and index images
#
# An experimental script that builds a custom operator catalog containing one or two
# versions of the same operator.
#
# The catalog is built in ./olm/catalog and doesn't actually require any other OLM manifests
# because is assumes the bundle images have been built and pushed to a registry.
#
# By default this script builds a catalog with two versions of the airflow operator.
#
# To test an operator upgrade you need to:
# 1. Build a single bundle catalog. Follow the comments on which lines to comment out.
# 2. Install the generated catalog source: `kubectl apply -f catalog-source.yaml -n stackable-operators`
# 3. Install the operator with OperatorHub UI (set upgrades to Automatic)
# 4. Reset the script and build the default catalog with two bundle versions.
# 5. Wait ~3 minutes for the catalog to update.
# 6. OLM should upgrade to the new version of the operator automatically.
#
# Assumes the bundle images are built and pushed to a registry as follows:
#
#./olm/build-manifests.py --openshift-versions v4.11-v4.15 --release 23.11.0 --repo-operator /home/razvan/repo/stackable/airflow-operator --replaces 23.4.1
#./olm/build-bundles.sh -r 23.11.0 -o airflow -c ~/repo/stackable/openshift-certified-operators -d
#
#./olm/build-manifests.py --openshift-versions v4.11-v4.15 --release 24.3.0 --repo-operator /home/razvan/repo/stackable/airflow-operator --replaces 23.11.0
#./olm/build-bundles.sh -r 24.3.0 -o airflow -c ~/repo/stackable/openshift-certified-operators -d
#
# See: https://olm.operatorframework.io/docs/reference/catalog-templates/#example
# for an example catalog with multiple bundles
#
export OPERATOR=commons

rm -rf olm/catalog
rm -rf olm/catalog.Dockerfile

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
	echo "- name: ${OPERATOR}-operator.v23.11.0"
	echo "- name: ${OPERATOR}-operator.v24.3.0"
	echo "  replaces: ${OPERATOR}-operator.v23.11.0"
	## comment out these two lines to build a single bundle catalog
	echo "- name: ${OPERATOR}-operator.v24.3.0-1"
	echo "  replaces: ${OPERATOR}-operator.v23.11.0"
	echo "  skips:"
	echo "  -  ${OPERATOR}-operator.v24.3.0"
} >>"olm/catalog/stackable-${OPERATOR}-operator.yaml"

echo "Render operator: ${OPERATOR}"
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:23.11.0" --output=yaml >>"olm/catalog/stackable-${OPERATOR}.v23.11.0-bundle.yaml"

# Add a new version to the catalog
# comment out this line to build a single bundle catalog
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:24.3.0" --output=yaml >>"olm/catalog/stackable-${OPERATOR}-v24.3.0-bundle.yaml"
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:24.3.0-1" --output=yaml >>"olm/catalog/stackable-${OPERATOR}-v24.3.0-1-bundle.yaml"

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
	echo "      interval: 3m"
} >catalog-source.yaml
