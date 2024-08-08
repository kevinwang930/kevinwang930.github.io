---
title: "kafka introduction"
date: 2024-06-27T19:16:55+08:00
categories:
- stream
- event
tags:
- event stream
- kafka
keywords:
- event stream
- kafka
#thumbnailImage: //example.com/image.jpg
---
Kafka is an open-source distributed event streaming platform 

<!--more-->
# Concept

Servers     Kafka is run as a cluster of one or more services that can span multiple data centers or cloud regions.

Brokers     one type of server, form the storage layer, store partitions 

Clients     allow one to read, write and process streams of events

Event       records the fact that something happened

Producer    Client application that publish(write) events to kafka

Consumer    client applications that subscribe to (read and process) these events.

Topics      Events are organized and durably stored in topics.

Partition   Topics are partitioned, spread over a number of buckets located on different kafka brokers

![partition](images/image.png)


# Producer

`KafkaProducer` A Kafka client that publishes records to the kafka cluster.
  The Producer is thread safe and sharing a single producer instance across threads will generally be faster than having multiple instances
  The `send()` method is asynchronous. When called, it adds the record to a buffer of pending record sends and immediately return.

`RecordAccumulator` acts as a queue that accumulates records into `MemoryRecords`








```plantuml
interface Producer<K, V> extends Closeable {
  Future<RecordMetadata> send(ProducerRecord<K, V> record)
  void flush()
}
class KafkaProducer<K, V> implements Producer {
    ProducerConfig producerConfig
    ProducerMetadata metadata
    RecordAccumulator accumulator
    Sender sender
    Thread ioThread
    Serializer<K> keySerializer
    Serializer<V> valueSerializer
    ProducerInterceptors<K, V> interceptors
}

class RecordAccumulator {
}

class Sender implements Runnable {
  KafkaClient client
  RecordAccumulator accumulator
  ProducerMetadata metadata
  TransactionManager transactionManager
}

class KafkaThread extends Thread 

class BufferPool

interface KafkaClient {
  boolean isReady(Node node, long now)
  boolean ready(Node node, long now)
  void send(ClientRequest request, long now)
  List<ClientResponse> poll(long timeout, long now)
  void disconnect(String nodeId)
  void close(String nodeId)
}

class NetworkClient implements KafkaClient {
  Selectable selector
  MetadataUpdater metadataUpdater
  ClusterConnectionStates connectionStates
}

class Selector implements Selectable {
  Selector nioSelector
  Map<String, KafkaChannel> channels
}

class ProducerMetadata {
  Map<String, Long> topics
  Set<String> newTopics
}

KafkaProducer o-- RecordAccumulator
KafkaProducer o-right- KafkaThread: ioThread
KafkaThread o-- Sender
RecordAccumulator o-- BufferPool
Sender o-- KafkaClient
NetworkClient o-- Selectable
KafkaProducer *-- ProducerMetadata


```

## Metadata

`Metadata` A class encapsulating some of the logic around metadata.
This class is shared by the client thread(for partitioning) and the background sender thread.

`Metadata` is maintained for only a subset of topics, which can be added to over time. 

`MetadataSnapshot` An internal immutable snapshot of nodes, topics, and partitions in the kafka cluster. 

```plantuml
class Metadata implements Closeable {
  MetadataSnapshot metadataSnapshot
  List<InetSocketAddress> bootstrapAddresses
}

class MetadataSnapshot {
  - unauthorizedTopics: Set<String>
  - clusterInstance: Cluster
  - metadataByPartition: Map<TopicPartition, PartitionMetadata>
  - invalidTopics: Set<String>
  - topicNames: Map<Uuid, String>
  - nodes: Map<Integer, Node>
  - clusterId: String
  - topicIds: Map<String, Uuid>
  - controller: Node
  - internalTopics: Set<String>
}

class Cluster {
  List<Node> nodes
  Node controller
  Map<TopicPartition, PartitionInfo> partitionsByTopicPartition
  Map<String, List<PartitionInfo>> partitionsByTopic
  Map<Integer, List<PartitionInfo>> partitionsByNode
  Map<Integer, Node> nodesById
  ClusterResource clusterResource
  Map<String, Uuid> topicIds
  Map<Uuid, String> topicNames
}

class ProducerMetadata {
  Map<String, Long> topics
  Set<String> newTopics
}

Metadata o-- MetadataSnapshot
MetadataSnapshot o-- Cluster
Metadata <|-right-  ProducerMetadata
```



## Producer Configs
* `batch.size`
  Producer will attempt to batch records together into fewer requests whenever multiple records are being sent to the same partition. This setting gives the upper bound of the batch size to be sent.
* `linger.ms`
  The producer groups together any records that arrive in between request transmissions into a single batched request. This setting gives the upper bound on the delay for batching.
* `retry.backoff.ms`
  the amount of time to wait before attempting to retry a failed request to a given topic
* `retry.backoff.max.ms`
  The maximum amount of time in milliseconds to wait when retrying a request to the broker that has repeatedly failed
* `reconnect.backoff.ms`
* `reconnect.backoff.max.ms`


# security

## SASL

Simple Authentication and Security Layer(SASL) is a framework for authentication and data security in internet protocols. It decouple authentication mechanisms from application protocols.

### 