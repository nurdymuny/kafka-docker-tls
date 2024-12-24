#!/usr/bin/env bash
set -o nounset \
    -o errexit \
    -o verbose \
    -o xtrace

# Variables
CA_PASSPHRASE="H62Rh4zA4opsOdsHylyENchmIqAldPCTa1c"
KEYSTORE_PASSPHRASE="cjIgiPUKEyIA66bu4Hz4W1YnrZaXCskwp9F"
KEY_PASS="ww6r0IaHBb945b9BB1oKYP6hDr5IhFpYAhz"
ORGANIZATION_NAME="NASA"
ORGANIZATION_UNIT="Luna"
LOCATION="Houston"
STATE="TX"
COUNTRY="US"
DAYS_VALID=3650  # 10 years
KEY_SIZE=2048    # RSA key size (could go 4096 if desired)

# Common name for your CA certificate
CA_COMMON_NAME="ca.luna.nasa.gov"

# The list of entities (e.g., brokers, clients) for which we'll generate keystores
ENTITIES=("broker1" "broker2" "broker3" "producer" "consumer")

# Create a CA key and certificate
openssl req \
  -new \
  -x509 \
  -days "${DAYS_VALID}" \
  -subj "/CN=${CA_COMMON_NAME}/OU=${ORGANIZATION_UNIT}/O=${ORGANIZATION_NAME}/L=${LOCATION}/S=${STATE}/C=${COUNTRY}" \
  -keyout lunaca.key \
  -out lunaca.crt \
  -passin  pass:"${CA_PASSPHRASE}" \
  -passout pass:"${CA_PASSPHRASE}"

# Kafkacat client key/cert
openssl genrsa \
  -des3 \
  -passout "pass:${KEYSTORE_PASSPHRASE}" \
  -out kafkacat.client.key \
  "${KEY_SIZE}"

openssl req \
  -passin  "pass:${KEYSTORE_PASSPHRASE}" \
  -passout "pass:${KEYSTORE_PASSPHRASE}" \
  -key kafkacat.client.key \
  -new \
  -out kafkacat.client.req \
  -subj "/CN=kafkacat.luna.nasa.gov/OU=${ORGANIZATION_UNIT}/O=${ORGANIZATION_NAME}/L=${LOCATION}/S=${STATE}/C=${COUNTRY}"

openssl x509 \
  -req \
  -CA lunaca.crt \
  -CAkey lunaca.key \
  -in kafkacat.client.req \
  -out kafkacat-ca-signed.pem \
  -days "${DAYS_VALID}" \
  -CAcreateserial \
  -passin "pass:${CA_PASSPHRASE}"


# Generate keystores and truststores for each entity (e.g., brokers, producer, consumer)
for ENTITY in "${ENTITIES[@]}"; do
  echo "Creating keystore and truststore for: ${ENTITY}"

  # 1) Generate a keypair in the keystore
  keytool -genkey -noprompt \
    -alias "${ENTITY}" \
    -dname "CN=${ENTITY}.luna.nasa.gov, OU=${ORGANIZATION_UNIT}, O=${ORGANIZATION_NAME}, L=${LOCATION}, S=${STATE}, C=${COUNTRY}" \
    -keystore "kafka.${ENTITY}.keystore.jks" \
    -keyalg RSA \
    -keysize "${KEY_SIZE}" \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEY_PASS}"

  # 2) Create a CSR (Certificate Signing Request)
  keytool -keystore "kafka.${ENTITY}.keystore.jks" \
    -alias "${ENTITY}" \
    -certreq \
    -file "${ENTITY}.csr" \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEY_PASS}"

  # 3) Sign the CSR with our CA
  openssl x509 \
    -req \
    -CA lunaca.crt \
    -CAkey lunaca.key \
    -in "${ENTITY}.csr" \
    -out "${ENTITY}-ca-signed.crt" \
    -days "${DAYS_VALID}" \
    -CAcreateserial \
    -passin pass:"${CA_PASSPHRASE}"

  # 4) Import the CA certificate into the keystore
  keytool -keystore "kafka.${ENTITY}.keystore.jks" \
    -alias "CARoot" \
    -import \
    -file lunaca.crt \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEY_PASS}" \
    -noprompt

  # 5) Import the signed certificate into the keystore
  keytool -keystore "kafka.${ENTITY}.keystore.jks" \
    -alias "${ENTITY}" \
    -import \
    -file "${ENTITY}-ca-signed.crt" \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEY_PASS}" \
    -noprompt

  # 6) Create a truststore and import the CA cert
  keytool -keystore "kafka.${ENTITY}.truststore.jks" \
    -alias "CARoot" \
    -import \
    -file lunaca.crt \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEY_PASS}" \
    -noprompt

  # 7) Create credentials files for convenience
  echo "${KEY_PASS}"     > "${ENTITY}_sslkey_creds"
  echo "${KEYSTORE_PASSPHRASE}" > "${ENTITY}_keystore_creds"
  echo "${KEYSTORE_PASSPHRASE}" > "${ENTITY}_truststore_creds"

  echo "Done for ${ENTITY}"
done

echo "All keystores and truststores successfully created."