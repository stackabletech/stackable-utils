# OLM installation files

The following steps describe the steps followed in the script used to build the catalog.

## Usage

Prerequisite is of course a running OpenShift cluster.

## Build and publish operator bundle image

Each catalog can contain several operator packages, and each operator package can contain multiple channels, each with its own bundles of different versions of the operator.

### Generate operator bundle (this is operator-specific)

    opm alpha bundle generate --directory manifests --package zookeeper-operator-package --output-dir bundle --channels stable --default stable

### Build bundle image

    docker build -t docker.stackable.tech/stackable/zookeeper-operator-bundle:23.1.0 -f bundle.Dockerfile .
  	docker push docker.stackable.tech/stackable/zookeeper-operator-bundle:23.1.0

### Validate bundle image

  	opm alpha bundle validate --tag docker.stackable.tech/stackable/zookeeper-operator-bundle:23.1.0 --image-builder docker

## Create catalog

    mkdir catalog
    opm generate dockerfile catalog

## Create a package for each operator

    opm init zookeeper-operator-package \
      --default-channel=stable \
      --description=./README.md \
      --output yaml > catalog/zookeeper-operator-package.yaml

    {
        echo "---"
        echo "schema: olm.channel"
        echo "package: zookeeper-operator-package"
        echo "name: stable"
        echo "entries:"
        echo "- name: zookeeper-operator.v23.1.0"
    } >> catalog/zookeeper-operator-package.yaml

NOTE: with the command below we can add the Stackable logo as icon.

    # add for each operator...
    opm render docker.stackable.tech/stackable/zookeeper-operator-bundle:23.1.0 --output=yaml >> catalog/zookeeper-operator-package.yaml

    # ...and then validate the entire catalog
    opm validate catalog

The catalog is correct if the command above returns successfully without any message. If the catalog doesn't validate, the operator will not install. Now build a catalog image and push it to the repository:

    docker build .  -f catalog.Dockerfile -t docker.stackable.tech/stackable/zookeeper-operator-catalog:latest
    docker push docker.stackable.tech/stackable/zookeeper-operator-catalog:latest

## Install catalog and the operator group

    kubectl apply -f catalog-source.yaml
    kubectl apply -f operator-group.yaml

## List available operators

    kubectl get packagemanifest -n stackable-operators

## Install operator

    kubectl apply -f subscription.yaml
