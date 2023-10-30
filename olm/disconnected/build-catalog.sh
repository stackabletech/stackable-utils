#!/bin/sh

BRANCH=main
VERSION=23.4.1
OPERATOR=zookeeper

REPOSITORY=registry.private.stackable.tech:5000
ORGANIZATION=sandbox

#git clone "git@github.com:stackabletech/openshift-certified-operators.git" --depth 1 --branch "${BRANCH}" --single-branch

cd "openshift-certified-operators/operators/stackable-${OPERATOR}-operator/${VERSION}"

rm -rf "bundle"
rm -rf "bundle.Dockerfile"

opm alpha bundle generate --directory manifests --package "stackable-${OPERATOR}-operator" --output-dir bundle --channels stable --default stable
cp metadata/*.yaml bundle/metadata/
docker build -t "${REPOSITORY}/stackable/${OPERATOR}-bundle:${VERSION}" -f bundle.Dockerfile .

docker push "${REPOSITORY}/stackable/${OPERATOR}-bundle:${VERSION}"

opm alpha bundle validate --tag "${REPOSITORY}/stackable/${OPERATOR}-bundle:${VERSION}" --image-builder docker

rm -rf catalog
mkdir -p catalog
opm init "stackable-${OPERATOR}-operator" \
	--default-channel=stable \
	--output yaml >"catalog/stackable-${OPERATOR}-operator.yaml"

echo "Add operator to package: ${OPERATOR}"
{
	echo "---"
	echo "schema: olm.channel"
	echo "package: stackable-${OPERATOR}-operator"
	echo "name: stable"
	echo "entries:"
	echo "- name: ${OPERATOR}-operator.v${VERSION}"
} >>"catalog/stackable-${OPERATOR}-operator.yaml"
echo "Render operator: ${OPERATOR}"
opm render --skip-tls-verify "${REPOSITORY}/stackable/${OPERATOR}-bundle:${VERSION}" --output=yaml >>"catalog/stackable-${OPERATOR}-operator.yaml"

echo "Validating catalog..."
opm validate catalog

echo "Build and push catalog for all ${OPERATOR} operator..."
cat >catalog.Dockerfile <<-EOS_CATALOG
	# The base image is expected to contain
	# /bin/opm (with a serve subcommand) and /bin/grpc_health_probe
	FROM quay.io/operator-framework/opm:latest

	# Configure the entrypoint and command
	ENTRYPOINT ["/bin/opm"]
	CMD ["serve", "/configs", "--cache-dir=/tmp/cache"]

	# Copy declarative config root into image at /configs and pre-populate serve cache
	ADD catalog /configs
	RUN ["/bin/opm", "serve", "/configs", "--cache-dir=/tmp/cache", "--cache-only"]

	# Set DC-specific label for the location of the DC root directory
	# in the image
	LABEL operators.operatorframework.io.index.configs.v1=/configs
EOS_CATALOG

docker build . -f catalog.Dockerfile -t "${REPOSITORY}/stackable/stackable-${OPERATOR}-catalog:${VERSION}"

docker push "${REPOSITORY}/stackable/stackable-${OPERATOR}-catalog:${VERSION}"
