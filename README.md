# Debezium Postgres source experiment

An experiment with Postgres change-data-capture (CDC) into Pulsar via [Pulsar
IO's](https://pulsar.apache.org/docs/en/io-overview/) built-in [Debezium
Postgres source
connector](https://pulsar.apache.org/docs/en/io-connectors/#debezium-postgresql).

At a high level, we'll set up a flow that looks like the following:

![System
diagram](/system-diagram.svg?raw=true&sanitize=true
"System diagram")

## Why?
Why go through all this trouble to set up such a system? Why not simply let your
application direcly write to both its database and Pulsar? In short, dual writes
are suceptible to 1) race conditions and 2) partial failures. For a good
explanation, see Martin Kleppmann's talk ["Using logs to build a solid data
infrastructure (or: why dual writes are a bad
idea)"](https://www.confluent.io/blog/using-logs-to-build-a-solid-data-infrastructure-or-why-dual-writes-are-a-bad-idea/).

## Hands on example
Run Postgres and Pulsar
```sh
docker-compose up
```

Start the Postgres source connector in the running Pulsar container
```sh
docker exec -it experiment-pulsar-connector_pulsar_1 /pulsar/bin/pulsar-admin source localrun --source-config-file /debezium-postgres-source-config.yaml
```
This leverages ["local run
mode"](https://pulsar.apache.org/docs/en/functions-deploy/#local-run-mode). In
production deployments, you'd likely want to leverage ["cluster mode"](https://pulsar.apache.org/docs/en/functions-deploy/#cluster-mode).

List topics
```sh
docker exec -it experiment-pulsar-connector_pulsar_1 /pulsar/bin/pulsar-admin topics list public/default
```

Consume the CDC topic corresponding to the Postgres table named `outbox`, in the
`db` database, in the `public` schema.
```sh
docker exec -it experiment-pulsar-connector_pulsar_1 /pulsar/bin/pulsar-client consume -s "mysubscription" persistent://public/default/db.public.outbox -n 0
```

Start a psql cli session
```sh
docker exec -it experiment-pulsar-connector_db_1 psql experiment experiment
```

Insert some data into the database
```sql
-- Insert some data
INSERT INTO outbox (aggregatetype, aggregateid, type, payload, mybytecol) VALUES('myaggregatetype1', 1, 'mytype', '{"hello":"world 1"}', decode('013d7d16d7ad4fefb61bd95b765c8ceb', 'hex'));
```

Watch the Pulsar consumer print output to stdout. It'll look something like this
(formatted with line breaks for improved readability):
```
----- got message -----
key:[eyJpZCI6ImJkZGVkZDE2LWJiOTQtNDExZi05MmE1LTI2ZDM1YjExNGZlMiJ9],

properties:[],

content:{
  "before": null,
  "after": {
    "id": "bddedd16-bb94-411f-92a5-26d35b114fe2",
    "ts": "2020-12-03T16:09:29.399905Z",
    "aggregatetype": "myaggregatetype1",
    "aggregateid": "1",
    "type": "mytype",
    "payload": "{\"hello\": \"world 1\"}",
    "mybytecol": "AT19FtetT++2G9lbdlyM6w=="
  },
  "source": {
    "version": "1.0.0.Final",
    "connector": "postgresql",
    "name": "db",
    "ts_ms": 1607011769400,
    "snapshot": "false",
    "db": "experiment",
    "schema": "public",
    "table": "outbox",
    "txId": 563,
    "lsn": 23517120,
    "xmin": null
  },
  "op": "c",
  "ts_ms": 1607011769410
}
```

## Postgres configuration notes
Some
[configuration](https://debezium.io/documentation/reference/1.0/connectors/postgresql.html)
is necessary to set up the replication slot on Postgres.

Configure the replication slot

`postgresql.conf`
```
# REPLICATION
wal_level = logical
max_wal_senders = 1
max_replication_slots = 1
```

(For this example repo, the below is optional. Not necessary locally nor with
super user) Configure the PostgreSQL server to allow replication to take place
between the server machine and the host on which the Debezium PostgreSQL
connector is running.

`/var/lib/postgresql/data/pg_hba.conf`
```
local   replication     experiment                          trust
host    replication     experiment  127.0.0.1/32            trust
host    replication     experiment  ::1/128                 trust
```

## Message transformations
[Pulsar IO](https://pulsar.apache.org/docs/en/io-overview/) (Pulsar's analog to
[Kafka Connect](https://docs.confluent.io/platform/current/connect/index.html))
does _not_ integrate message transformations like Kafka does via [Kafka Connect
Single Message
Transformations](https://docs.confluent.io/platform/current/connect/transforms/overview.html)
(SMTs).

Pulsar IO's main focus seems to be connecting external systems via business
logic agnostic source and sink adapters. Instead, Pulsar's built-in mechanism
for message transformations is [Pulsar
Functions](https://pulsar.apache.org/docs/en/functions-overview/).


For example, there exists a Kafka Connect SMT for [event outbox message
routing](https://debezium.io/documentation/reference/configuration/topic-routing.html)
which can be used out-of-the-box with Kafka. Unfortunately, there is not an
out-of-the-box equivalent for Pulsar.

To achieve something similar in Pulsar, one might look to one of the following:

1. Apply a custom routing transformation on the raw Pulsar IO Postgres source
   data that was sent to the topic. For example, via Pulsar Functions, a stream
   processor of your choice (i.e. Flink), or your own service running on your
   compute platform of choice. This type of approach is explored in
   [experiment-event-outbox-router](https://github.com/ypt/experiment-event-outbox-router).
2. Leverage [Debezium
   Engine](https://debezium.io/documentation/reference/development/engine.html)
   to implement your own Postgres CDC logical replication consumer.