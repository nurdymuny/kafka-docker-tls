# Intro

Kafka provides event streaming to enable a near realtime events to publish/consume by the clients.

This repo will help us to understand how to easy it is to enable SSL on Kafka Broker.

# Prerequisite
- docker 
- docker-compose
- keytool (Java utility)

# Project
```sh
docker-compose.yaml
|tls|
# KeyStore config
|___| broker-ks-creds  # Contains password for keystore 
|___| key-creds        # Contains password for the key(alias) for keystore
|___| kafka.broker.keystore.jks  
# Trust store
|___| truststore-creds # Contains password for trust store 
|___| kafka.broker.truststore.jks  


```


# How to generate keystore & Truststore

Any server requires at least a Keystore(to serve the requests) and a Truststore (To make the request to other servers/systems). Similarly, we will need to create both -

## 1. Keystore
Please run the below command to generate it
```sh
$ keytool -genkeypair -dname "CN=localhost, OU=Integartion, O=dhaka, L=New Delhi, ST=New Delhi, C=IN"  -keypass password  -storepass changeit -validity 9999 -keystore kafka.broker.keystore.jks -alias localhost -ext SAN=DNS:localhost,IP:127.0.0.1

#Warning:
#The JKS keystore uses a proprietary format. It is recommended to migrate to PKCS12 which is an industry standard format using "keytool -importkeystore -srckeystore kafka.broker.keystore.jks -destkeystore kafka.broker.keystore.jks -deststoretype pkcs12".
```
We have successfully created a keystore.
### Verify

```sh
 keytool -list -keystore kafka.broker.keystore.jks -storepass changeit
#Keystore type: jks
#Keystore provider: SUN

#Your keystore contains 1 entry

#localhost, Mar 10, 2021, PrivateKeyEntry,
#Certificate fingerprint (SHA1): F7:FD:F1:13:20:D0:54:C6:C8:7E:EB:22:1D:2A:2D:C7:30:DD:2C:28

#Warning:
#The JKS keystore uses a proprietary format. It is recommended to migrate to PKCS12 which is an industry standard format using "keytool -importkeystore -srckeystore kafka.broker.keystore.jks -destkeystore kafka.broker.keystore.jks -deststoretype pkcs12".

```
You might have noticed the keystore contains 1 entry with the details.


## 2. Truststore
Truststore is used by any client to make a secure request to any server which support TLS.
> I will import the public cert of the same keystore.

- How to import a public cert?
```sh
keytool -exportcert -keystore kafka.broker.keystore.jks  -storepass changeit -alias localhost -file public.cert
#Certificate stored in file <public.cert>

```
- Create a truststore using the exported file

```sh
 keytool -importcert -keystore kafka.broker.truststore.jks  -storepass changeit -alias localhost -file public.cert --noprompt
Certificate was added to keystore
```

Verify the truststore
```sh
$ keytool -list -keystore kafka.broker.truststore.jks -storepass changeit
#Keystore type: jks
#Keystore provider: SUN

#Your keystore contains 1 entry

#localhost, Mar 10, 2021, trustedCertEntry,
#Certificate fingerprint (SHA1): F7:FD:F1:13:20:D0:54:C6:C8:7E:EB:22:1D:2A:2D:C7:30:DD:2C:28

```

So far we have create a keystore and truststore for Kafka broker.
- kafka.broker.```keystore```.jks
- kafka.broker.```truststore```.jks

# Generate Kafka credentials 
Kafka requires the passwords to open the keystore/truststore and use the certificate. Below are the files which contains password strings -
```sh
$ echo 'changeit' > broker-ks-creds && \ # Contains password for keystore 
$ echo 'password' > key-creds && \         # Contains password for the key(alias) for keystore

# Trust store
$ echo 'changeit' >truststore-creds # Contains password for trust store 
$ ls
#-rw-r--r-- 1 root root    9 Mar 10 03:13 broker-ks-creds
#-rw-r--r-- 1 root root 2019 Mar 10 02:54 kafka.broker.keystore.jks
#-rw-r--r-- 1 root root 1339 Mar 10 03:06 kafka.broker.truststore.jks
#-rw-r--r-- 1 root root    9 Mar 10 03:13 key-creds
#-rw-r--r-- 1 root root 1273 Mar 10 03:01 public.cert
#-rw-r--r-- 1 root root    9 Mar 10 03:13 truststore-creds
```

So far we have created all the required files to enable TLS on Kafka broker.

# Docker-compose 
Kafka provides a quick running guide with multiple ways of your choice. However, I'll be using docker-compose to quickly spin up the containers in my local virutal machine.

> Please find the latest docker-compose file [here](https://docs.confluent.io/platform/current/quickstart/ce-docker-quickstart.html), from official documentations.

docker-compose file has multiple services, we will change some of the configuration under ```broker``` service, Please comment and add details as mentioned below under environment variable section -
```yaml

  broker:
    image: confluentinc/cp-server:6.1.0
    hostname: broker
    container_name: broker
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
      - "9101:9101"
      ## TLS Security Port
      - "9093:9093"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      ## ** *********************************************
      #  ** Please comment below mentioned 2 variables ** 
      ## ** *********************************************      
      #KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      #KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:29092,PLAINTEXT_HOST://localhost:9092

      KAFKA_METRIC_REPORTERS: io.confluent.metrics.reporter.ConfluentMetricsReporter
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_CONFLUENT_LICENSE_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_CONFLUENT_BALANCER_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_JMX_PORT: 9101
      KAFKA_JMX_HOSTNAME: localhost
      KAFKA_CONFLUENT_SCHEMA_REGISTRY_URL: http://schema-registry:8081
      CONFLUENT_METRICS_REPORTER_BOOTSTRAP_SERVERS: broker:29092
      CONFLUENT_METRICS_REPORTER_TOPIC_REPLICAS: 1
      CONFLUENT_METRICS_ENABLE: 'true'
      CONFLUENT_SUPPORT_CUSTOMER_ID: 'anonymous'
      ## ** ************************************************************ 
      ## ** Please add below mentioned extra variables to enable TLS  **
      #  ** Security TLS Enablement                                   **
      ## ** ************************************************************
      KAFKA_SSL_KEYSTORE_FILENAME: kafka.broker.keystore.jks
      KAFKA_SSL_KEYSTORE_CREDENTIALS: broker-ks-creds
      KAFKA_SSL_KEY_CREDENTIALS: key-creds
      KAFKA_SSL_TRUSTSTORE_FILENAME: kafka.broker.truststore.jks
      KAFKA_SSL_TRUSTSTORE_CREDENTIALS: truststore-creds
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: SSL:SSL,PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT 
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:29092,PLAINTEXT_HOST://localhost:9092,SSL://localhost:9093


```