#!/bin/bash
#
# Create local private registry with a self signed certificate
#
#

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

# generate registry certificate (for one year)
openssl req -newkey rsa:4096 -nodes -sha256 \
	-keyout "${CERT_FOLDER}/${KEY_NAME}" -x509 -days 365 \
	-out "${CERT_FOLDER}/${CERT_NAME}" \
	-subj "/C=DE/ST=Schleswig-Holstein/L=Wedel/O=Stackable/OU=Engineering/CN=${REG_NAME}" \
	-addext "subjectAltName = DNS:${REG_NAME}"

# generate registry user credentials
docker run --rm --entrypoint htpasswd httpd:2 -Bbn ${REG_USER} ${REG_PASSWORD} >"${AUTH_FOLDER}/htpasswd"

# create the registry container
docker run --rm -d --name ${REG_CONTAINER} --net host -p 5000:5000 \
	-v ${PWD}/${DATA_FOLDER}:/var/lib/registry:z -v ${PWD}/${AUTH_FOLDER}:/auth:z \
	-e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry" \
	-e "REGISTRY_HTTP_SECRET=10f207a4cbba51bf00755b5a50718966" \
	-e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v ${PWD}/${CERT_FOLDER}:/certs:z \
	-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${CERT_NAME} \
	-e REGISTRY_HTTP_TLS_KEY=/certs/${KEY_NAME} docker.io/library/registry:2

# test the registry
sleep 5
echo curl --fail -k -u "${REG_USER}:${REG_PASSWORD}" https://${REG_NAME}:5000/v2/_catalog
curl --fail -k -u "${REG_USER}:${REG_PASSWORD}" https://${REG_NAME}:5000/v2/_catalog

# # push a test image to the registry
# docker login "${REG_NAME}:5000" -u "${REG_USER}" -p "${REG_PASSWORD}"
# docker pull docker.stackable.tech/stackable/testing-tools:0.2.0-stackable23.7.0
# docker tag docker.stackable.tech/stackable/testing-tools:0.2.0-stackable23.7.0 "${REG_NAME}:5000/stackable/testing-tools:0.2.0-stackable23.7.0"
# docker push "${REG_NAME}:5000/stackable/testing-tools:0.2.0-stackable23.7.0"
