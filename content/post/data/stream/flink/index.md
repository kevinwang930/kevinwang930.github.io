---
title: "Apache Flink internals"
date: 2026-10-06T19:00:00+02:00
categories:
- data
- stream
- flink
tags:
- data
- stream
- flink
keywords:
- flink
- streaming
#thumbnailImage: //example.com/image.jpg
---

**Apache Flink** is a distributed engine for continuous (and bounded) dataflow programs. A job is a graph of operators; the runtime places parallel **tasks** on **TaskManagers**, keeps operator **state** local to those tasks, and advances time with **watermarks** so windows and timers close at well-defined points.

<!--more-->

---

## 1. Overview


**Apache Flink** is a distributed engine for continuous (and bounded) **dataflow** programs. A job is a graph of operators. The runtime places parallel **tasks** on workers, keeps operator **state** local to those tasks, and advances **event time** with **watermarks** so windows and timers close at well-defined points.

![Flink overview: client, sources, cluster, sinks](images/flink-overview-usage.svg)

Default execution is **streaming**: records flow continuously and checkpoints snapshot state for recovery. The same operators can run in **batch** style (`RuntimeExecutionMode.BATCH`) when every input is bounded. Parallelism is per operator (or a job default): a logical operator with parallelism `p` becomes `p` **subtasks** that share no mutable state. Keyed state is partitioned by key group so rescale can move groups without rewriting every key.

### Usage example

You build a pipeline with the DataStream API (`StreamExecutionEnvironment`) or the Table / SQL API—sources in, transforms, sinks out—then call `execute` (or submit a JAR) so the cluster runs the job until it is cancelled, fails past recovery, or finishes when all bounded inputs end. A typical job:

```java
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
env.enableCheckpointing(10_000);

env.fromSource(ordersSource, watermarkStrategy, "orders")
    .map(new ParseOrder())
    .keyBy(Order::getUserId)
    .window(TumblingEventTimeWindows.of(Duration.ofMinutes(1)))
    .aggregate(new CountPerUser())
    .sinkTo(kafkaSink);

env.execute("orders-per-minute");
```

Here Kafka (or another connector) is the source, keyed windows hold per-user counts in operator state, and another connector is the sink.

### Cluster roles

That job is scheduled onto a Flink cluster with two process roles:

| Role | Responsibility |
|------|----------------|
| **JobManager** | Accepts jobs, builds the scheduling plan, coordinates checkpoints, recovers failures |
| **TaskManager** | Hosts **task slots**; runs one or more subtasks; holds keyed/operator state locally |

One JobManager is the leader for a given high-availability setup. The client submits to the JobManager. TaskManagers register slots with the ResourceManager; the JobMaster claims slots and deploys tasks into them. Source and sink connectors run inside those tasks—the JobManager never sees individual records. When operators repartition (for example after `keyBy`), TaskManagers exchange records over pipelined network buffers (shuffle). Checkpoints are triggered by the JobManager and acknowledged by the tasks.

---

## 2. Job graph translation

User code does not schedule threads directly. Flink lowers the API graph in stages until each TaskManager runs concrete `StreamTask` instances:

1. **API `Transformation`s** — each DataStream call appends a node to a list on the environment.
2. **`StreamGraph`** — `StreamGraphGenerator` turns that list into `StreamNode` / `StreamEdge` (partitioners, exchange mode).
3. **`JobGraph`** — `StreamingJobGraphGenerator` collapses chainable sequences into `JobVertex` units and places network edges where repartition is required.
4. **`ExecutionGraph`** — the JobMaster expands each vertex to `parallelism` execution vertices and deploys `StreamTask`s onto slots.

![orders-per-minute job graph translation](images/flink-graph-translation.svg)

The stages below reuse the §1 **orders-per-minute** example:

```text
API:     orders -> ParseOrder -> keyBy(userId) -> window -> aggregate -> kafkaSink
Stream:  [orders] --fwd--> [ParseOrder] --hash--> [window+agg] --fwd--> [kafkaSink]
Job:     JobVertex_A(orders+ParseOrder)  ==network==>  JobVertex_B(window+agg+kafkaSink)
Exec:    A.0 A.1 ...     shuffle      B.0 B.1 ...
```

`StreamGraph.getJobGraph` is the bridge the client (or Application Mode cluster entrypoint) uses before the JobMaster materializes the `ExecutionGraph`. Failures restart from the last completed checkpoint by resetting tasks and restoring state handles recorded in that checkpoint.

### 2.1 StreamGraph generation

Building a `StreamGraph` is a two-phase procedure on the client. User code first accumulates API metadata; only an explicit `getStreamGraph` / `execute` turns that metadata into a graph. Nothing processes records yet—operator factories create runtime **`StreamOperator`s** later, when tasks deploy on workers.

Procedures:

1. **API call** (§2.1.1) — each `fromSource` / `map` / `keyBy` / … returns a **`DataStream`** (or related) handle and appends a **`Transformation`** to `StreamExecutionEnvironment`’s list.
2. **StreamGraph translation** (§2.1.2) — `getStreamGraph` / `execute` hands that list to **`StreamGraphGenerator`**, which dispatches each **`Transformation`** to a **`TransformationTranslator`** that writes **`StreamNode`s** / **`StreamEdge`s** (`fwd`, `hash`, …).

#### 2.1.1 API call

When user code writes a DataStream job, each call like `fromSource`, `map`, or `keyBy` looks like it builds a pipeline—but at this stage Flink only records what was requested. Every call returns a **`DataStream`** (or a close relative such as `KeyedStream`) for further chaining, and behind the scenes it adds a **`Transformation`** to a list on **`StreamExecutionEnvironment`**. That list is the real program so far; the `DataStream` objects are just convenient handles. No tasks run and no records move until the code later asks for a graph or calls `execute`.

```plantuml
@startuml

class StreamExecutionEnvironment {
  - transformations : List
  - parallelism : int
  + fromSource(Source, WatermarkStrategy, String) : DataStreamSource
  + addOperator(Transformation) : void
  + getParallelism() : int
  + getStreamGraph() : StreamGraph
}

class DataStream {
  # environment : StreamExecutionEnvironment
  # transformation : Transformation
  + getExecutionEnvironment() : StreamExecutionEnvironment
  + getTransformation() : Transformation
  + map(MapFunction) : SingleOutputStreamOperator
  + keyBy(KeySelector) : KeyedStream
  + transform(String, TypeInformation, StreamOperatorFactory) : SingleOutputStreamOperator
  + sinkTo(Sink) : DataStreamSink
}

class SingleOutputStreamOperator {
  + name(String) : SingleOutputStreamOperator
  + uid(String) : SingleOutputStreamOperator
  + setParallelism(int) : SingleOutputStreamOperator
}

class DataStreamSource

class KeyedStream {
  - keySelector : KeySelector
  - keyType : TypeInformation
  + window(WindowAssigner) : WindowedStream
  + reduce(ReduceFunction) : SingleOutputStreamOperator
}

class WindowedStream {
  - input : KeyedStream
  - windowAssigner : WindowAssigner
  + aggregate(AggregateFunction) : SingleOutputStreamOperator
  + reduce(ReduceFunction) : SingleOutputStreamOperator
}

class Transformation {
  # id : int
  # name : String
  # uid : String
  # parallelism : int
  # outputType : TypeInformation
  + getId() : int
  + getName() : String
  + getInputs() : List
  + getOutputType() : TypeInformation
  + getParallelism() : int
}

class OneInputTransformation {
  - input : Transformation
  - operatorFactory : StreamOperatorFactory
  + getOperatorFactory() : StreamOperatorFactory
  + getInputs() : List
}

class PartitionTransformation {
  - partitioner : StreamPartitioner
  - exchangeMode : StreamExchangeMode
  + getPartitioner() : StreamPartitioner
  + getExchangeMode() : StreamExchangeMode
  + getInputs() : List
}

class ReduceTransformation {
  - input : Transformation
  - reducer : ReduceFunction
  - keySelector : KeySelector
  - keyTypeInfo : TypeInformation
  + getReducer() : ReduceFunction
  + getKeySelector() : KeySelector
  + getInputs() : List
}

DataStream <|-- SingleOutputStreamOperator
DataStream <|-- KeyedStream
SingleOutputStreamOperator <|-- DataStreamSource

WindowedStream --> KeyedStream : holds

StreamExecutionEnvironment --> DataStream : fromSource / transforms
StreamExecutionEnvironment --> Transformation : owns list
DataStream --> Transformation : wraps
Transformation <|-- OneInputTransformation
Transformation <|-- PartitionTransformation
Transformation <|-- ReduceTransformation
KeyedStream ..> ReduceTransformation : reduce
@enduml
```

```java
// DataStream.map: create a Transformation and register it on the env (no task yet)
public <R> SingleOutputStreamOperator<R> map(MapFunction<T, R> mapper) {
    return transform(
        "Map",
        getType().getTypeClass() /* simplified */,
        new OneInputTransformation<>(
            this.transformation,
            "Map",
            new MapOperatorFactory<>(mapper),
            TypeExtractor.getMapReturnTypes(mapper, getType()),
            parallelism));
}

protected <R> SingleOutputStreamOperator<R> transform(
        String operatorName,
        TypeInformation<R> outTypeInfo,
        OneInputTransformation<T, R> transformation) {
    // registers on StreamExecutionEnvironment.transformations
    getExecutionEnvironment().addOperator(transformation);
    return new SingleOutputStreamOperator<>(getExecutionEnvironment(), transformation);
}
```

For **orders-per-minute**, after the fluent chain the environment’s list holds transforms for `orders`, `ParseOrder`, `keyBy(userId)`, window+aggregate, and `kafkaSink`—still only metadata.

#### 2.1.2 StreamGraph translation

When user code calls `execute` (or `getStreamGraph`), the client turns the environment’s **`Transformation`** list into a **`StreamGraph`**. **`StreamGraphGenerator`** does not hard-code per-type `instanceof` logic for the common operators; it looks up a **`TransformationTranslator`** in `translatorMap` and delegates with a **`TransformationTranslator.Context`** (`ContextImpl`) that exposes the in-progress `StreamGraph`, already-translated parent node ids, and recursive `transform(...)`. Each translator writes **`StreamNode`s** / **`StreamEdge`s** (or a virtual partition node for `keyBy`) into the graph. Runtime **`StreamOperator`** instances are still not created here; factories on the nodes create them later when tasks deploy on workers.

```plantuml
@startuml

class StreamExecutionEnvironment {
  - transformations : List
  + getStreamGraph() : StreamGraph
  + execute(String) : JobClient
}

class StreamGraphGenerator {
  - transformations : List
  - translatorMap : Map
  + generate() : StreamGraph
  - transform(Transformation) : Collection
}

interface TransformationTranslator {
  + translateForStreaming(Transformation, Context) : Collection
  + translateForBatch(Transformation, Context) : Collection
}

interface "TransformationTranslator.Context" as Context {
  + getStreamGraph() : StreamGraph
  + getStreamNodeIds(Transformation) : Collection
  + getSlotSharingGroup() : String
  + transform(Transformation) : Collection
}

class ContextImpl {
  - streamGraphGenerator : StreamGraphGenerator
  - streamGraph : StreamGraph
  - slotSharingGroup : String
}

class SourceTransformationTranslator
class OneInputTransformationTranslator
class PartitionTransformationTranslator
class ReduceTransformationTranslator
class SinkTransformationTranslator

class StreamGraph {
  - streamNodes : Map
  - sources : Set
  - sinks : Set
  - virtualPartitionNodes : Map
  - virtualSideOutputNodes : Map
  + addOperator(int, String, StreamOperatorFactory, int) : void
  + addEdge(int, int, StreamPartitioner, StreamExchangeMode) : void
  + addVirtualPartitionNode(int, int, StreamPartitioner, StreamExchangeMode) : void
  + getSourceIDs() : Collection
  + getSinkIDs() : Collection
  + getJobGraph() : JobGraph
}

class StreamNode {
  - id : int
  - operatorName : String
  - parallelism : int
  - operatorFactory : StreamOperatorFactory
  - inEdges : List
  - outEdges : List
  - statePartitioners : KeySelector[]
  - stateKeySerializer : TypeSerializer
  + getOperatorFactory() : StreamOperatorFactory
  + getInEdges() : List
  + getOutEdges() : List
  + getStatePartitioners() : KeySelector[]
  + setStatePartitioners(KeySelector...) : void
}

interface StreamOperatorFactory {
  + createStreamOperator(Context) : StreamOperator
  + getStreamOperatorClass(ClassLoader) : Class
}

class SourceOperatorFactory
class SimpleOperatorFactory {
  - operator : StreamOperator
}
class SimpleUdfStreamOperatorFactory
class WindowOperatorFactory {
  - windowAssigner : WindowAssigner
  - trigger : Trigger
  - windowFunction : InternalWindowFunction
  - keySelector : KeySelector
}
class SinkWriterOperatorFactory

class StreamOperator
class StreamMap
class WindowOperator

class StreamEdge {
  - sourceId : int
  - targetId : int
  - partitioner : StreamPartitioner
  - exchangeMode : StreamExchangeMode
}

StreamExecutionEnvironment ..> StreamGraphGenerator : getStreamGraph()
StreamGraphGenerator --> TransformationTranslator : translatorMap
StreamGraphGenerator ..> StreamGraph : generate
StreamGraphGenerator ..> ContextImpl : creates per transform
Context <|.. ContextImpl
ContextImpl --> StreamGraphGenerator
ContextImpl --> StreamGraph
TransformationTranslator ..> Context : translate*(..., context)
TransformationTranslator <|.. SourceTransformationTranslator
TransformationTranslator <|.. OneInputTransformationTranslator
TransformationTranslator <|.. PartitionTransformationTranslator
TransformationTranslator <|.. ReduceTransformationTranslator
TransformationTranslator <|.. SinkTransformationTranslator
StreamGraph --> StreamNode : streamNodes
StreamGraph --> StreamNode : sources / sinks
StreamNode --> StreamOperatorFactory : operatorFactory
StreamOperatorFactory <|.. SourceOperatorFactory
StreamOperatorFactory <|.. SimpleOperatorFactory
StreamOperatorFactory <|.. WindowOperatorFactory
StreamOperatorFactory <|.. SinkWriterOperatorFactory
SimpleOperatorFactory <|-- SimpleUdfStreamOperatorFactory
SimpleUdfStreamOperatorFactory --> StreamMap : ParseOrder
WindowOperatorFactory --> WindowOperator : window+aggregate
StreamOperator <|-- StreamMap
StreamOperator <|-- WindowOperator
StreamNode --> StreamEdge : inEdges / outEdges
@enduml
```

```java
// Client entry: build StreamGraph, then continue toward JobGraph / cluster
public JobClient execute(String jobName) throws Exception {
    StreamGraph streamGraph = getStreamGraph(); // clears transformations by default
    streamGraph.setJobName(jobName);
    return execute(streamGraph);
}

public StreamGraph getStreamGraph() {
    return getStreamGraph(true);
}

public StreamGraph getStreamGraph(boolean clearTransformations) {
    StreamGraph graph = new StreamGraphGenerator(transformations, /* config */).generate();
    if (clearTransformations) {
        transformations.clear();
    }
    return graph;
}

// StreamGraphGenerator: recurse from sinks, dispatch by Transformation class
private Collection<Integer> transform(Transformation<?> transform) {
    if (alreadyTransformed.containsKey(transform)) {
        return alreadyTransformed.get(transform);
    }
    TransformationTranslator<?, Transformation<?>> translator =
        translatorMap.get(transform.getClass());
    // e.g. OneInputTransformation -> OneInputTransformationTranslator
    //      PartitionTransformation -> PartitionTransformationTranslator
    Collection<Integer> ids = shouldExecuteInBatchMode
        ? translator.translateForBatch(transform, context)
        : translator.translateForStreaming(transform, context);
    alreadyTransformed.put(transform, ids);
    return ids;
}

// translatorMap (excerpt for orders-per-minute)
translatorMap.put(SourceTransformation.class, new SourceTransformationTranslator<>());
translatorMap.put(OneInputTransformation.class, new OneInputTransformationTranslator<>());
translatorMap.put(PartitionTransformation.class, new PartitionTransformationTranslator<>());
translatorMap.put(ReduceTransformation.class, new ReduceTransformationTranslator<>());
translatorMap.put(SinkTransformation.class, new SinkTransformationTranslator<>());
```

For **orders-per-minute**, translators produce this `StreamGraph` content:

```text
Transformation                     Translator                              Graph effect
-------------------------------    ------------------------------------    ------------------------------------------
SourceTransformation(orders)       SourceTransformationTranslator          StreamNode orders
OneInputTransformation(ParseOrder) OneInputTransformationTranslator        StreamNode ParseOrder + fwd edge
PartitionTransformation(keyBy)     PartitionTransformationTranslator       virtual partition (no physical node)
OneInputTransformation(window+agg) OneInputTransformationTranslator        StreamNode window+aggregate + hash edge
SinkTransformation(kafkaSink)      SinkTransformationTranslator            StreamNode kafkaSink + fwd edge

StreamNodes:
  orders              SourceOperatorFactory
  ParseOrder          MapOperatorFactory
  window+aggregate    WindowOperatorFactory
  kafkaSink           SinkOperatorFactory

StreamEdges:
  orders           --fwd-->              ParseOrder
  ParseOrder       --hash(userId)-->     window+aggregate
  window+aggregate --fwd-->              kafkaSink
```

`keyBy` is handled by **`PartitionTransformationTranslator`**: it registers a virtual node so the downstream edge carries the hash partitioner—not a separate running operator.

### 2.2 JobGraph creation

After the `StreamGraph` exists, the client (or Application Mode entrypoint) builds a **`JobGraph`** via **`StreamingJobGraphGenerator`**. This step does not deploy tasks yet: it decides **operator chaining**—which `StreamNode`s share one thread / mailbox as a single **`JobVertex`**—and where **network** boundaries must remain. Chainable **forward** edges collapse into one vertex; **hash** / rebalance edges become **`JobEdge`s** between vertices (intermediate result partitions).

```plantuml
@startuml

interface Pipeline {
  + getJobGraph(ClassLoader) : JobGraph
}

class StreamGraph {
  - streamNodes : Map
  - sources : Set
  - sinks : Set
  + getJobGraph(ClassLoader) : JobGraph
}

interface PipelineExecutor {
  + execute(Pipeline, Configuration, ClassLoader) : CompletableFuture
}

class LocalExecutor {
  - configuration : Configuration
  - miniClusterFactory : Function
  + {static} create(Configuration) : LocalExecutor
  + execute(Pipeline, Configuration, ClassLoader) : CompletableFuture
  - getJobGraph(Pipeline, Configuration, ClassLoader) : JobGraph
}

abstract class AbstractSessionClusterExecutor {
  - clusterClientFactory : ClusterClientFactory
  - configuration : Configuration
  + execute(Pipeline, Configuration, ClassLoader) : CompletableFuture
}

class RemoteExecutor {
  + {static} NAME : String
}

class YarnSessionClusterExecutor
class KubernetesSessionClusterExecutor

abstract class AbstractJobClusterExecutor {
  - clusterClientFactory : ClusterClientFactory
  - configuration : Configuration
  + execute(Pipeline, Configuration, ClassLoader) : CompletableFuture
}

class YarnJobClusterExecutor

class StreamingJobGraphGenerator {
  + createJobGraph(StreamGraph) : JobGraph
  - createChain(StreamNode) : List
  + isChainable(StreamEdge, StreamNode, StreamNode) : boolean
}

class JobGraph {
  - taskVertices : List
  - serializedExecutionConfig : ExecutionConfig
  + addVertex(JobVertex) : void
}

class JobVertex {
  - parallelism : int
  - invokableClass : Class
  - operatorIDs : List
  + connectNewDataSetAsInput(JobVertex, DistributionPattern) : JobEdge
}

class StreamConfig {
  - chainedConfigs : Map
  - operatorName : String
  - statePartitioner : KeySelector
}

class IntermediateDataSet {
  - producer : JobVertex
}

class JobEdge {
  - distributionPattern : DistributionPattern
  - source : IntermediateDataSet
}

Pipeline <|.. StreamGraph

PipelineExecutor <|.. LocalExecutor
PipelineExecutor <|.. AbstractSessionClusterExecutor
PipelineExecutor <|.. AbstractJobClusterExecutor

AbstractSessionClusterExecutor <|-- RemoteExecutor
AbstractSessionClusterExecutor <|-- YarnSessionClusterExecutor
AbstractSessionClusterExecutor <|-- KubernetesSessionClusterExecutor

AbstractJobClusterExecutor <|-- YarnJobClusterExecutor

PipelineExecutor ..> StreamGraph : execute
StreamGraph ..> StreamingJobGraphGenerator : getJobGraph()
StreamingJobGraphGenerator ..> JobGraph : createJobGraph
JobGraph *-- JobVertex
JobVertex *-- StreamConfig
JobVertex *-- IntermediateDataSet
IntermediateDataSet *-- JobEdge
@enduml
```

```java
// --- Step 1: user code / env.execute ---
// builds StreamGraph (§2.1.2), then submits that pipeline
public JobClient execute(String jobName) throws Exception {
    StreamGraph streamGraph = getStreamGraph(); // Transformation list -> StreamGraph
    streamGraph.setJobName(jobName);
    return execute(streamGraph);
}

// --- Step 2: pick a PipelineExecutor (local / remote / yarn / k8s, …) ---
public JobClient executeAsync(StreamGraph streamGraph) throws Exception {
    PipelineExecutorFactory factory =
        executorServiceLoader.getExecutorFactory(configuration);
    return factory.getExecutor(configuration)
        .execute(streamGraph, configuration, userClassloader)
        .get();
}

// --- Step 3: executor turns Pipeline (StreamGraph) into JobGraph, then submits ---
// e.g. LocalExecutor / AbstractSessionClusterExecutor
public CompletableFuture<JobClient> execute(
        Pipeline pipeline, Configuration configuration, ClassLoader userClassloader)
        throws Exception {
    JobGraph jobGraph = PipelineExecutorUtils.getJobGraph(pipeline, configuration);
    // submit jobGraph to MiniCluster / cluster ...
    return submit(jobGraph);
}

// PipelineExecutorUtils / StreamGraph path (simplified)
static JobGraph getJobGraph(Pipeline pipeline, Configuration configuration) {
    StreamGraph streamGraph = (StreamGraph) pipeline;
    return streamGraph.getJobGraph(userClassLoader);
}

// --- Step 4: StreamGraph -> JobGraph (chaining) ---
public JobGraph getJobGraph(ClassLoader userClassLoader) {
    return StreamingJobGraphGenerator.createJobGraph(userClassLoader, this, jobId);
}

public static JobGraph createJobGraph(StreamGraph streamGraph) {
    JobGraph jobGraph = new JobGraph(streamGraph.getJobID(), streamGraph.getJobName());
    for (Integer sourceId : streamGraph.getSourceIDs()) {
        createChain(sourceId, streamGraph, jobGraph); // walk edges, merge fwd chains
    }
    return jobGraph;
}

// Chaining predicate (simplified): only fwd edges with matching parallelism merge
static boolean isChainable(StreamEdge edge, StreamNode up, StreamNode down) {
    return edge.getPartitioner() instanceof ForwardPartitioner
        && up.getParallelism() == down.getParallelism()
        && down.getInEdges().size() == 1
        && up.isSameSlotSharingGroup(down)
        && down.isChainingEnabled();
}
// Chain head -> JobVertex + StreamConfig chain
// Non-chainable edge -> IntermediateDataSet + JobEdge (network shuffle)
```

**Orders-per-minute — from `StreamGraph` to `JobGraph`**

Starting `StreamGraph` (from §2.1.2):

```text
StreamNodes:  orders --fwd--> ParseOrder --hash(userId)--> window+aggregate --fwd--> kafkaSink
```

Chaining decisions:

| StreamEdge | Partitioner | `isChainable`? | Result |
|---|---|---|---|
| orders → ParseOrder | `fwd` | yes (same parallelism) | same chain |
| ParseOrder → window+aggregate | `hash(userId)` | **no** | network boundary |
| window+aggregate → kafkaSink | `fwd` | yes | same chain |

Resulting `JobGraph`:

```text
JobVertex_A  (chain head = orders)
  chained operators:  orders , ParseOrder
  invokable:          SourceStreamTask / StreamTask (serialized StreamConfig chain)
  parallelism:        p
       │
       │  JobEdge  (hash / POINTWISE or ALL_TO_ALL key-group shuffle)
       │  IntermediateDataSet between A and B
       ▼
JobVertex_B  (chain head = window+aggregate)
  chained operators:  window+aggregate , kafkaSink
  statePartitioner:   userId KeySelector (on window op StreamConfig)
  parallelism:        p
```

So two deployment units, not four: `orders` and `ParseOrder` share one mailbox (no network hop); after the hash shuffle, `window+aggregate` and `kafkaSink` share another. The `keyBy` never becomes its own `JobVertex`—only the **edge** between A and B.

### 2.3 JobGraph → ExecutionGraph

On the JobManager, the **JobMaster** turns the submitted `JobGraph` into an **`ExecutionGraph`**: each `JobVertex` expands to `parallelism` **`ExecutionVertex`** instances (subtasks `A.0`, `A.1`, …). The scheduler requests slots, deploys tasks, and each successful deployment starts a **`StreamTask`** (or source/sink specialization) in a TaskManager slot. Failures reset executions and restore state from the latest completed checkpoint.

```plantuml
@startuml
skinparam classAttributeIconSize 0

class JobMaster {
  + startJobExecution()
}

class ExecutionGraph {
  Map verticesById
  + scheduleForExecution()
  + failGlobal(Throwable)
}

class ExecutionJobVertex {
  ExecutionVertex[] taskVertices
  int parallelism
}

class ExecutionVertex {
  int subTaskIndex
  + getCurrentExecutionAttempt() : Execution
}

class Execution {
  + deploy()
  + fail(Throwable)
}

class TaskDeploymentDescriptor
class StreamTask {
  + invoke()
}

JobMaster ..> ExecutionGraph : build from JobGraph
ExecutionGraph --> ExecutionJobVertex
ExecutionJobVertex --> ExecutionVertex : parallelism
ExecutionVertex --> Execution : attempt
Execution ..> TaskDeploymentDescriptor : deploy
TaskDeploymentDescriptor ..> StreamTask : TaskManager runs
@enduml
```

```java
// JobMaster (simplified): JobGraph -> ExecutionGraph -> schedule
ExecutionGraph executionGraph = DefaultExecutionGraphBuilder.buildGraph(
    jobGraph,
    configuration,
    blobWriter,
    /* ... */);

executionGraph.scheduleForExecution();

// Each ExecutionVertex gets an Execution attempt that deploys to a slot
Execution execution = executionVertex.getCurrentExecutionAttempt();
LogicalSlot slot = slotPool.allocateSlot(/* ... */);
execution.deploy(slot); // TaskManager receives TaskDeploymentDescriptor

// On the worker: load invokable (e.g. OneInputStreamTask) and run
StreamTask<?, ?> task = createInvokable(deployment);
task.invoke(); // mailbox loop: records, timers, checkpoint barriers
```

After this step the logical pipeline is concrete parallel work: TaskManagers run `StreamTask`s, exchange buffers on network edges, and acknowledge checkpoints back to the JobMaster.

---

## 3. TaskManagers, slots, and data exchange

A TaskManager is a JVM worker. It advertises a fixed number of **slots**; each slot can run one parallel pipeline slice (one subtask from each chained JobVertex sharing that slot in slot-sharing groups). CPU and managed memory are budgeted per slot.

Records leave a chain through a **result partition** and enter the downstream chain through an **input gate**. Exchange modes matter:

| Mode | Behavior |
|------|----------|
| **Pipelined** | Producer sends buffers as soon as they fill; consumer reads concurrently (default streaming) |
| **Blocking** | Producer finishes a partition before the consumer reads (common in batch) |

Partitioners on `StreamEdge` decide routing: `ForwardPartitioner` keeps data local to the same subtask index, `KeyGroupStreamPartitioner` (after `keyBy`) hashes keys into key groups, `RebalancePartitioner` round-robins for load balance.

```mermaid
flowchart TB
  subgraph TM1["TaskManager 1"]
    S0["Slot 0\nStreamTask A.0"]
    S1["Slot 1\nStreamTask A.1"]
  end
  subgraph TM2["TaskManager 2"]
    S2["Slot 0\nStreamTask B.0"]
    S3["Slot 1\nStreamTask B.1"]
  end
  S0 -->|"hash(key) buffers"| S2
  S0 -->|"hash(key) buffers"| S3
  S1 -->|"hash(key) buffers"| S2
  S1 -->|"hash(key) buffers"| S3
```

Backpressure is local: when a consumer’s input buffers fill, credit-based flow control slows the upstream output. That pressure propagates through pipelined edges until sources throttle or buffer timeouts fire.

---

## 4. State and checkpoints

Stateful operators store values in a **state backend** (heap, RocksDB, or others). After `keyBy`, state is **keyed**: each key group lives with the subtask that owns that group. Operator state (e.g. source offsets as list state) is redistributed on rescale by redistribution schemes declared on the state descriptor.

Consistency across the distributed graph uses **checkpoints**. The JobMaster’s `CheckpointCoordinator` periodically triggers a checkpoint:

1. Allocate a checkpoint id and storage location.
2. Send a trigger to source tasks (and notify operator coordinators when present).
3. Sources inject a **checkpoint barrier** into each outgoing stream.
4. Barriers flow with the data. On alignment (exactly-once), a task waits until the barrier arrives on all input channels for that checkpoint, then snapshots its state and forwards the barrier downstream.
5. Tasks acknowledge the coordinator with state handles. When all acknowledge, the checkpoint is marked **completed** and becomes the recovery baseline.

```mermaid
sequenceDiagram
  participant CC as CheckpointCoordinator
  participant Src as Source StreamTask
  participant Op as Downstream StreamTask
  participant Store as Checkpoint storage
  CC->>Src: trigger checkpoint n
  Src->>Store: snapshot source state
  Src->>Op: CheckpointBarrier(n)
  Note over Op: align inputs, then snapshot
  Op->>Store: snapshot keyed/operator state
  Op->>CC: AcknowledgeCheckpoint(n)
  Src->>CC: AcknowledgeCheckpoint(n)
  CC->>CC: mark checkpoint n complete
```

Exactly-once end-to-end additionally requires transactional sinks (or two-phase commit operators) that commit only after the checkpoint that includes their side effects completes. At-least-once can skip full barrier alignment so barriers overtake buffered data; recovery may replay more records.

Savepoints are user-triggered checkpoints with a stable format used for stop-with-savepoint, deploy upgrades, and rescaling. Externalized checkpoints keep metadata after job termination when retention is configured.

On recovery, the JobMaster resumes from the latest completed checkpoint: tasks restore state handles, sources re-emit from the offsets stored in that snapshot, and in-flight data after the barriers is discarded or replayed according to the mode.

---

## 5. Event time and watermarks

Flink distinguishes **processing time** (wall clock on the machine) from **event time** (timestamps carried by records). Event-time windows and timers fire from the progress of **watermarks**, not from wall-clock ticks.

A `WatermarkStrategy` supplies:

- a `TimestampAssigner` that stamps each record;
- a `WatermarkGenerator` that emits watermark values (periodically or on records).

`WatermarkStrategy.forBoundedOutOfOrderness(Duration)` is the common generator: it tracks the max observed event timestamp and emits `maxEventTs - outOfOrderness` (minus one millisecond in the usual formulation), so late arrivals within the bound can still join open windows.

```java
DataStream<Event> events = env.fromSource(
    source,
    WatermarkStrategy
        .<Event>forBoundedOutOfOrderness(Duration.ofSeconds(5))
        .withTimestampAssigner((e, ts) -> e.getEventTimeMillis()),
    "events");

events
    .keyBy(Event::getKey)
    .window(TumblingEventTimeWindows.of(Duration.ofMinutes(1)))
    .aggregate(new CountAggregate())
    .sinkTo(sink);
```

Watermarks propagate downstream. At a multi-input operator, the effective watermark is the **minimum** across inputs (and channels): the operator must not advance event time past data that might still arrive on a slower channel. Idle sources can be marked idle so they do not hold the minimum forever.

```text
records:   t=10  t=12  t=11  t=18  t=20
watermark:              ....  W=13       W=15
bound = 5s  =>  W ≈ maxEventTs - 5s

window [0,60s): closes when watermark >= 60s
```

Late records that arrive after the watermark has passed their window are either dropped, sent to a side output configured for lateness, or allowed into still-open windows if `allowedLateness` extends the lifetime. Processing-time windows ignore watermarks and fire on timer service wall-clock deadlines.

---

## 6. Minimal job shape

A complete streaming job always has the same outer shape: environment, source with timestamps if event time is used, keyed stateful (or windowed) operators, sink, and checkpoint configuration.

```java
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
env.enableCheckpointing(10_000); // ms
env.getCheckpointConfig().setCheckpointingConsistencyMode(CheckpointingMode.EXACTLY_ONCE);

env.fromSource(source, watermarkStrategy, "src")
    .map(new ParseFn())
    .keyBy(Event::getKey)
    .process(new StatefulCountFn())
    .sinkTo(sink);

env.execute("order-count");
```

`StatefulCountFn` would hold a `ValueState<Long>` (or `MapState`) under the current key; after every checkpoint that state is part of the acknowledged snapshot. With RocksDB, large keyed state stays on local disk and is uploaded incrementally according to the configured checkpoint storage (JobManager + durable filesystem, or a fully remote incremental scheme).

The JobManager never sees individual records. It only schedules tasks, triggers checkpoints, and restores state handles. Throughput and latency are determined by slot count, chain boundaries, network buffers, state backend, and watermark delay—not by a central broker inside Flink itself.
