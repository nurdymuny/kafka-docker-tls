#!/usr/bin/env bash
set -o nounset \
    -o errexit \
    -o verbose \
    -o xtrace

###############################################################################
# Variables (update as needed)
###############################################################################
CA_PASSPHRASE="H62Rh4zA4opsOdsHylyENchmIqAldPCTa1c"
KEYSTORE_PASSPHRASE="cjIgiPUKEyIA66bu4Hz4W1YnrZaXCskwp9F"
ORGANIZATION_NAME="NASA"
ORGANIZATION_UNIT="Luna"
LOCATION="Houston"
STATE="TX"
COUNTRY="US"
DAYS_VALID=3650   # 10 years
KEY_SIZE=2048     # RSA key size (could go 4096 if desired)

# Common Name for the CA
CA_COMMON_NAME="ca.luna.nasa.gov"

# Entities for which we generate keystores (e.g., brokers, producer, consumer)
ENTITIES=("broker1" "broker2" "broker3" "producer" "consumer")

###############################################################################
# 1) Create a CA key and certificate (self-signed)
###############################################################################
openssl req \
  -new \
  -x509 \
  -days "${DAYS_VALID}" \
  -subj "/CN=${CA_COMMON_NAME}/OU=${ORGANIZATION_UNIT}/O=${ORGANIZATION_NAME}/L=${LOCATION}/ST=${STATE}/C=${COUNTRY}" \
  -keyout lunaca.key \
  -out lunaca.crt \
  -passin  pass:"${CA_PASSPHRASE}" \
  -passout pass:"${CA_PASSPHRASE}"

###############################################################################
# 2) (Optional) Generate Kafkacat client key/cert
###############################################################################
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
  -subj "/CN=kafkacat.luna.nasa.gov/OU=${ORGANIZATION_UNIT}/O=${ORGANIZATION_NAME}/L=${LOCATION}/ST=${STATE}/C=${COUNTRY}"

openssl x509 \
  -req \
  -CA lunaca.crt \
  -CAkey lunaca.key \
  -in kafkacat.client.req \
  -out kafkacat-ca-signed.pem \
  -days "${DAYS_VALID}" \
  -CAcreateserial \
  -passin "pass:${CA_PASSPHRASE}"

###############################################################################
# 3) Generate keystores and truststores for each entity
###############################################################################
for ENTITY in "${ENTITIES[@]}"; do
  echo "Creating keystore and truststore for: ${ENTITY}"

  # a) Generate a keypair in the keystore (JKS)
  keytool -genkey -noprompt \
    -alias "${ENTITY}" \
    -dname "CN=${ENTITY}.luna.nasa.gov, OU=${ORGANIZATION_UNIT}, O=${ORGANIZATION_NAME}, L=${LOCATION}, ST=${STATE}, C=${COUNTRY}" \
    -keystore "kafka.${ENTITY}.keystore.jks" \
    -storetype JKS \
    -keyalg RSA \
    -keysize "${KEY_SIZE}" \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEYSTORE_PASSPHRASE}"

  # b) Create a CSR
  keytool -keystore "kafka.${ENTITY}.keystore.jks" \
    -alias "${ENTITY}" \
    -certreq \
    -file "${ENTITY}.csr" \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEYSTORE_PASSPHRASE}"

  # c) Sign the CSR with our CA
  openssl x509 \
    -req \
    -CA lunaca.crt \
    -CAkey lunaca.key \
    -in "${ENTITY}.csr" \
    -out "${ENTITY}-ca-signed.crt" \
    -days "${DAYS_VALID}" \
    -CAcreateserial \
    -passin pass:"${CA_PASSPHRASE}"

  # d) Import the CA cert into the keystore
  keytool -keystore "kafka.${ENTITY}.keystore.jks" \
    -alias "CARoot" \
    -import \
    -file lunaca.crt \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEYSTORE_PASSPHRASE}" \
    -noprompt \
    -storetype JKS

  # e) Import the signed certificate into the keystore
  keytool -keystore "kafka.${ENTITY}.keystore.jks" \
    -alias "${ENTITY}" \
    -import \
    -file "${ENTITY}-ca-signed.crt" \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEYSTORE_PASSPHRASE}" \
    -noprompt \
    -storetype JKS

  # f) Create a truststore (JKS) and import the CA cert
  keytool -keystore "kafka.${ENTITY}.truststore.jks" \
    -alias "CARoot" \
    -import \
    -file lunaca.crt \
    -storepass "${KEYSTORE_PASSPHRASE}" \
    -keypass "${KEYSTORE_PASSPHRASE}" \
    -noprompt \
    -storetype JKS

  # g) Create credentials files
  echo "${KEYSTORE_PASSPHRASE}" > "${ENTITY}_sslkey_creds"
  echo "${KEYSTORE_PASSPHRASE}" > "${ENTITY}_keystore_creds"
  echo "${KEYSTORE_PASSPHRASE}" > "${ENTITY}_truststore_creds"

  echo "Done for ${ENTITY}"
done

echo "All keystores and truststores successfully created."
