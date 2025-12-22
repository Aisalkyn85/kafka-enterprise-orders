FROM confluentinc/cp-kafka-connect:7.6.1

RUN confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:latest
RUN confluent-hub install --no-prompt couchbase/kafka-connect-couchbase:latest

CMD ["bash", "-c", "connect-distributed /etc/kafka/connect-distributed.properties"]

