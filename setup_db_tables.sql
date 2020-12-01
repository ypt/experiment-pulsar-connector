-- set up replication permissions
-- https://debezium.io/documentation/reference/1.0/connectors/postgresql.html#PostgreSQL-permissions
CREATE ROLE name REPLICATION LOGIN;

-- set up table
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE outbox (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- NOTE: this is not in the outbox Kafka Connect SMT spec
  aggregatetype VARCHAR(255) NOT NULL,
  aggregateid VARCHAR(255) NOT NULL,
  type VARCHAR(255) NOT NULL,
  payload JSONB NOT NULL,
  mybytecol BYTEA NOT NULL -- NOTE: this is not in the outbox Kafka Connect SMT spec. Added this additional column to test support for plain ol' binary data (i.e. Avro serialized). https://debezium.io/documentation/reference/configuration/outbox-event-router.html#avro-as-payload-format
);

-- NOTE: Pulsar IO (Pulsar's analog to Kafka Connect) does _not_ support event
-- outbox routing out of the box - which Kafka Connect _does_ support, via SMT.
-- For example, the following is Kafka only:
-- https://debezium.io/documentation/reference/configuration/topic-routing.html