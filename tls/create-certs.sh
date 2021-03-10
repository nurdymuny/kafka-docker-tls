#!/bin/bash

set -o nounset \
    -o errexit \
    -o verbose \
    -o xtrace

# Generate CA key
openssl req -new -x509 -keyout snakeoil-ca-1.key -out snakeoil-ca-1.crt -days 365 -subj '/CN=ca1.test.changeit.io/OU=TEST/O=changeit/L=PaloAlto/S=Ca/C=US' -passin pass:changeit -passout pass:changeit
# openssl req -new -x509 -keyout snakeoil-ca-2.key -out snakeoil-ca-2.crt -days 365 -subj '/CN=ca2.test.changeit.io/OU=TEST/O=changeit/L=PaloAlto/S=Ca/C=US' -passin pass:changeit -passout pass:changeit

# Kafkacat
openssl genrsa -des3 -passout "pass:changeit" -out kafkacat.client.key 1024
openssl req -passin "pass:changeit" -passout "pass:changeit" -key kafkacat.client.key -new -out kafkacat.client.req -subj '/CN=kafkacat.test.changeit.io/OU=TEST/O=changeit/L=PaloAlto/S=Ca/C=US'
openssl x509 -req -CA snakeoil-ca-1.crt -CAkey snakeoil-ca-1.key -in kafkacat.client.req -out kafkacat-ca1-signed.pem -days 9999 -CAcreateserial -passin "pass:changeit"



for i in broker1 broker2 broker3 producer consumer
do
	echo $i
	# Create keystores
	keytool -genkey -noprompt \
				 -alias $i \
				 -dname "CN=$i.test.changeit.io, OU=TEST, O=changeit, L=PaloAlto, S=Ca, C=US" \
				 -keystore kafka.$i.keystore.jks \
				 -keyalg RSA \
				 -storepass changeit \
				 -keypass changeit

	# Create CSR, sign the key and import back into keystore
	keytool -keystore kafka.$i.keystore.jks -alias $i -certreq -file $i.csr -storepass changeit -keypass changeit

	openssl x509 -req -CA snakeoil-ca-1.crt -CAkey snakeoil-ca-1.key -in $i.csr -out $i-ca1-signed.crt -days 9999 -CAcreateserial -passin pass:changeit

	keytool -keystore kafka.$i.keystore.jks -alias CARoot -import -file snakeoil-ca-1.crt -storepass changeit -keypass changeit

	keytool -keystore kafka.$i.keystore.jks -alias $i -import -file $i-ca1-signed.crt -storepass changeit -keypass changeit

	# Create truststore and import the CA cert.
	keytool -keystore kafka.$i.truststore.jks -alias CARoot -import -file snakeoil-ca-1.crt -storepass changeit -keypass changeit

  echo "changeit" > ${i}_sslkey_creds
  echo "changeit" > ${i}_keystore_creds
  echo "changeit" > ${i}_truststore_creds
done
