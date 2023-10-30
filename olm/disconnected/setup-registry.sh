#!/bin/bash
#
# Create local private registry with a self signed certificate
#
# TODO: the approach with the self signed certificate has been dropped.
# This setup will not work with OpenShift (or any Kubernetes) until
# the self signed certificate is added on all nodes of the cluster.
# One possible way to do this with a cluster where we don't have access
# to the nodes (like CRC) is to use a DaemonSet with a hostPath.
#
  
done

REG_CONTAINER="private-registry"

REG_USER="reguser"
REG_PASSWORD="regpassword"

CERT_FOLDER=data/registry/certs
AUTH_FOLDER=data/registry/auth
DATA_FOLDER=data/registry/data

# We use the REG_NAME as host name for the registry.
# Make sure you add it to your /etc/hosts
REG_NAME="registry.private.stackable.tech"
KEY_NAME="${REG_NAME}.key"
CERT_NAME="${REG_NAME}.crt"

rm -rf data

mkdir -p "$CERT_FOLDER"
mkdir -p "$AUTH_FOLDER"
mkdir -p "$DATA_FOLDER"

cat >cert.conf <<-CERTCONF
	[req]
	default_bits  = 2048
	distinguished_name = req_distinguished_name
	req_extensions = req_ext
	x509_extensions = v3_req
	prompt = no
	[req_distinguished_name]
	countryName = DE
	stateOrProvinceName = N/A
	localityName = N/A
	organizationName = Self-signed certificate
	commonName = ${REG_NAME}
	[req_ext]
	subjectAltName = @alt_names
	[v3_req]
	subjectAltName = @alt_names
	[alt_names]
	DNS.1 = ${REG_NAME}
	IP.1 = 192.168.2.117
CERTCONF

# generate registry certificate (for one year)
openssl req -newkey rsa:4096 -nodes -sha256 \
	-keyout "${CERT_FOLDER}/${KEY_NAME}" -x509 -days 365 \
	-out "${CERT_FOLDER}/${CERT_NAME}" \
	-config cert.conf

# generate registry user credentials
docker run --rm --entrypoint htpasswd --user $(id -u):$(id -g) httpd:2 -Bbn ${REG_USER} ${REG_PASSWORD} >"${AUTH_FOLDER}/htpasswd"

# create the registry container
docker run --rm -d --name ${REG_CONTAINER} --user $(id -u):$(id -g) --net host -p 5000:5000 \
	-v ${PWD}/${DATA_FOLDER}:/var/lib/registry:z -v ${PWD}/${AUTH_FOLDER}:/auth:z \
	-e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry" \
	-e "REGISTRY_HTTP_SECRET=10f207a4cbba51bf00755b5a50718966" \
	-e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
	-v ${PWD}/${CERT_FOLDER}:/certs:z \
	-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${CERT_NAME} \
	-e REGISTRY_HTTP_TLS_KEY=/certs/${KEY_NAME} \
	docker.io/library/registry:2

# test the registry
sleep 5
echo curl --fail -k -u "${REG_USER}:${REG_PASSWORD}" https://${REG_NAME}:5000/v2/_catalog
curl --fail -k -u "${REG_USER}:${REG_PASSWORD}" https://${REG_NAME}:5000/v2/_catalog

# # push a test image to the registry
# docker login "${REG_NAME}:5000" -u "${REG_USER}" -p "${REG_PASSWORD}"
# docker pull docker.stackable.tech/stackable/testing-tools:0.2.0-stackable23.7.0
# docker tag docker.stackable.tech/stackable/testing-tools:0.2.0-stackable23.7.0 "${REG_NAME}:5000/stackable/testing-tools:0.2.0-stackable23.7.0"
# docker push "${REG_NAME}:5000/stackable/testing-tools:0.2.0-stackable23.7.0"
