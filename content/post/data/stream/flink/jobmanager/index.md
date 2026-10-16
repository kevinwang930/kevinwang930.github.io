---
title: "Apache Flink internals - JobManager"
date: 2026-10-16T17:20:00+02:00
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
- jobmanager
- jobgraph
---

The client submits a **`StreamGraph`**. The **JobManager** (the per-job **JobMaster**) compiles that plan into a **`JobGraph`**, expands it to an **`ExecutionGraph`**, and schedules tasks. 

<!--more-->

---

## 1. JobGraph creation

**`StreamingJobGraphGenerator`** runs on the cluster, while the JobMaster builds its scheduler. `DefaultSchedulerFactory` and `AdaptiveSchedulerFactory` both do this:

```java
JobGraph jobGraph;
if (executionPlan instanceof JobGraph) {
    jobGraph = (JobGraph) executionPlan;
} else if (executionPlan instanceof StreamGraph) {
    jobGraph = ((StreamGraph) executionPlan).getJobGraph(userCodeLoader);
}

// StreamGraph.getJobGraph
return StreamingJobGraphGenerator.createJobGraph(userClassLoader, this, jobId, applicationId);
```

That compile decides **operator chaining**: which `StreamNode`s share one thread as a single **`JobVertex`**, and where a **network** boundary must remain. Chainable **forward** edges collapse into one vertex. **Hash** / rebalance edges become **`JobEdge`s** (intermediate result partitions).

![orders-per-minute job graph translation](images/flink-graph-translation.svg)

```plantuml
@startuml

class JobMaster {
  - executionPlan : ExecutionPlan
  - schedulerNG : SchedulerNG
  - createScheduler() : SchedulerNG
}

interface SchedulerNGFactory {
  + createInstance(ExecutionPlan, ...) : SchedulerNG
}

class DefaultSchedulerFactory
class AdaptiveSchedulerFactory

class StreamGraph {
  + getJobGraph(ClassLoader) : JobGraph
}

class StreamingJobGraphGenerator {
  + createJobGraph(ClassLoader, StreamGraph, JobID) : JobGraph
  - createChain(Integer) : void
  + isChainable(StreamEdge, StreamNode, StreamNode) : boolean
}

class JobGraph {
  - taskVertices : List
  + addVertex(JobVertex) : void
}

class JobVertex {
  - parallelism : int
  - invokableClass : Class
  - operatorIDs : List
}

class StreamConfig {
  - chainedConfigs : Map
  - statePartitioner : KeySelector
}

class IntermediateDataSet {
  - producer : JobVertex
}

class JobEdge {
  - distributionPattern : DistributionPattern
  - source : IntermediateDataSet
}

SchedulerNGFactory <|.. DefaultSchedulerFactory
SchedulerNGFactory <|.. AdaptiveSchedulerFactory
JobMaster ..> SchedulerNGFactory : createScheduler
DefaultSchedulerFactory ..> StreamGraph : getJobGraph
AdaptiveSchedulerFactory ..> StreamGraph : getJobGraph
StreamGraph ..> StreamingJobGraphGenerator : createJobGraph
StreamingJobGraphGenerator ..> JobGraph
JobGraph *-- JobVertex
JobVertex *-- StreamConfig
JobVertex *-- IntermediateDataSet
IntermediateDataSet *-- JobEdge
@enduml
```

```java
public static JobGraph createJobGraph(StreamGraph streamGraph) {
    JobGraph jobGraph = new JobGraph(streamGraph.getJobID(), streamGraph.getJobName());
    for (Integer sourceId : streamGraph.getSourceIDs()) {
        createChain(sourceId, streamGraph, jobGraph);
    }
    return jobGraph;
}

static boolean isChainable(StreamEdge edge, StreamNode up, StreamNode down) {
    return edge.getPartitioner() instanceof ForwardPartitioner
        && up.getParallelism() == down.getParallelism()
        && down.getInEdges().size() == 1
        && up.isSameSlotSharingGroup(down)
        && down.isChainingEnabled();
}
```

**Orders-per-minute**

```text
StreamNodes:  orders --fwd--> ParseOrder --hash(userId)--> window+aggregate --fwd--> kafkaSink
```

| StreamEdge | Partitioner | `isChainable`? | Result |
|---|---|---|---|
| orders → ParseOrder | `fwd` | yes (same parallelism) | same chain |
| ParseOrder → window+aggregate | `hash(userId)` | **no** | network boundary |
| window+aggregate → kafkaSink | `fwd` | yes | same chain |

```text
JobVertex_A  (chain head = orders)
  chained operators:  orders , ParseOrder
  parallelism:        p
       │
       │  JobEdge  (hash / key-group shuffle)
       ▼
JobVertex_B  (chain head = window+aggregate)
  chained operators:  window+aggregate , kafkaSink
  statePartitioner:   userId KeySelector
  parallelism:        p
```

Two deployment units, not four. `keyBy` is only the edge between A and B.

---


## 2. ExecutionGraph

On the JobManager, the **JobMaster** expands the `JobGraph` from §1 into an **`ExecutionGraph`**: each `JobVertex` expands to `parallelism` **`ExecutionVertex`** instances (subtasks `A.0`, `A.1`, …). The scheduler requests slots, deploys tasks, and each successful deployment starts a **`StreamTask`** (or source/sink specialization) in a TaskManager slot. Failures reset executions and restore state from the latest completed checkpoint.

```plantuml
@startuml

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
