#
# Build an operator catalog.
#
# An experimental script that builds a custom operator catalog containing one or
# more operators and one or more versions of each operator.
#
# The catalog is built in ./olm/catalog and doesn't actually require any other OLM manifests
# because is assumes the bundle images have been built and pushed to a registry.
#
# It take as argument the name of an operator to add to the catalog.
#
# The operator versions and the upgrade paths are hard coded in the script (for now).
#
# Call it multiple times with different operators to build a catalog with multiple operators.
#
# To start fresh, delete the olm/catalog directory.
#
# To start fresh with a single operator remove the olm/catalog/${OPERATOR} directory.
#
# This script also generates a catalog source yaml file that you can apply to your cluster.
# Once the catalog is loaded by OLM, you can update it and OLM is automatically
# pull in the new versions.
#
# To install operators from this catalog, use the OperatorHub UI and filter by "Source: Stackable Catalog".
#
# Assumes the bundle images are built and pushed to a registry as follows:
#
#./olm/build-manifests.py --openshift-versions v4.11-v4.15 --release 23.11.0 --repo-operator /home/razvan/repo/stackable/${OPERATOR}-operator --replaces nothing
#./olm/build-bundles.sh -r 23.11.0 -o ${OPERATOR} -c ~/repo/stackable/openshift-certified-operators -d
#
# The secret and listener op bundles are special and need to be built manually.
#
# See: https://olm.operatorframework.io/docs/reference/catalog-templates/#example
# for an example catalog with multiple bundles
#
export OPERATOR="$1"

rm -rf olm/catalog/${OPERATOR}
rm -rf olm/catalog.Dockerfile

mkdir -p olm/catalog/${OPERATOR}
opm generate dockerfile olm/catalog

opm init "stackable-${OPERATOR}-operator" \
	--default-channel=stable \
	--output yaml >"olm/catalog/${OPERATOR}/stackable-${OPERATOR}-operator.yaml"

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
	echo "- name: ${OPERATOR}-operator.v24.3.0-1"
	echo "  replaces: ${OPERATOR}-operator.v23.11.0"
	echo "  skips:"
	echo "  -  ${OPERATOR}-operator.v24.3.0"
} >>"olm/catalog/${OPERATOR}/stackable-${OPERATOR}-operator.yaml"

echo "Render operator: ${OPERATOR}"
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:23.11.0" --output=yaml >>"olm/catalog/${OPERATOR}/stackable-${OPERATOR}.v23.11.0-bundle.yaml"
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:24.3.0" --output=yaml >>"olm/catalog/${OPERATOR}/stackable-${OPERATOR}-v24.3.0-bundle.yaml"
opm render "docker.stackable.tech/sandbox/${OPERATOR}-bundle:24.3.0-1" --output=yaml >>"olm/catalog/${OPERATOR}/stackable-${OPERATOR}-v24.3.0-1-bundle.yaml"

echo "Validating catalog..."
opm validate olm/catalog

echo "Build catalog..."
docker build olm -f olm/catalog.Dockerfile -t "docker.stackable.tech/sandbox/stackable-catalog:multi"
docker push "docker.stackable.tech/sandbox/stackable-catalog:multi"

export VERSION="multi"

echo "Generating catalog source..."
{
	echo "---"
	echo "apiVersion: operators.coreos.com/v1alpha1"
	echo "kind: CatalogSource"
	echo "metadata:"
	echo "  name: stackable-catalog"
	echo "spec:"
	echo "  sourceType: grpc"
	echo "  image: docker.stackable.tech/sandbox/stackable-catalog:${VERSION}"
	echo "  displayName: Stackable Catalog"
	echo "  publisher: Stackable GmbH"
	echo "  updateStrategy:"
	echo "    registryPoll:"
	echo "      interval: 3m"
} >catalog-source.yaml
