---
title: "Java Stream internals"
date: 2026-06-27T18:02:29+08:00
categories:
- java
tags:
- java
- stream
keywords:
- stream
#thumbnailImage: //example.com/image.jpg
---
`java.util.stream.Stream` is the public face of Java 8's functional-style aggregate operations. Under the hood it is not a data structure — it is a **lazy pipeline** of linked stages backed by a `Spliterator` source. Intermediate operations such as `filter` and `map` only extend the pipeline; computation begins when a terminal operation such as `collect` or `forEach` triggers evaluation. This document traces the OpenJDK implementation centered on `Stream`, its pipeline machinery, and how elements flow from source to result.
<!--more-->

---

## 1. Overview

The `java.util.stream` package implements `Stream`, `IntStream`, `LongStream`, and `DoubleStream` — all backed by the same pipeline skeleton (`ReferencePipeline` / `*Pipeline`):

- **`BaseStream`** — common lifecycle API (`sequential`, `parallel`, `spliterator`, `close`)
- **`AbstractPipeline`** — linked list of pipeline stages; owns evaluation logic
- **`PipelineHelper`** — abstract view of a pipeline segment used during terminal evaluation
- **`Sink`** — per-stage consumer chain that pushes elements through operations
- **`TerminalOp`** — encapsulates a terminal operation's sequential/parallel execution
- **`Spliterator`** — external iterator/splitter abstraction for the data source

A typical call like `list.stream().filter(p).map(f).collect(toList())` builds a four-stage pipeline (source → filter → map → terminal) without touching any elements until `collect` runs.

---

## 2. Architecture

The design separates **declaration** (building the pipeline) from **execution** (traversing the source). Public methods on `Stream` delegate to package-private pipeline classes and operation factories.

![Java Stream architecture layers](images/stream-architecture.svg)

### 2.1 Pipeline lifecycle

1. **Creation** — `StreamSupport.stream(spliterator, parallel)` constructs a `ReferencePipeline.Head` (the source stage).
2. **Chaining** — Each intermediate operation appends a new `AbstractPipeline` stage via the `previousStage` / `nextStage` links and marks the upstream stage as `linkedOrConsumed`.
3. **Terminal trigger** — A terminal method calls `AbstractPipeline.evaluate(TerminalOp)`, which obtains the source `Spliterator`, then dispatches to `evaluateSequential` or `evaluateParallel`.
4. **Traversal** — `PipelineHelper.wrapSink` builds a chained `Sink` from the terminal sink back to the source; `wrapAndCopyInto` drives the spliterator to push elements through every stage.

For sequential pipelines without stateful intermediate operations, the framework **fuses** all stages into a single pass — filter, map, and reduce can run with minimal intermediate buffering.

For parallel pipelines with **stateful** operations (`sorted`, `distinct`, `limit` in some cases), the pipeline is split into **segments** at each stateful stage; each segment is evaluated separately and its output becomes the next segment's input.

---

## 3. Structure

### 3.1 Class hierarchy

```plantuml
@startuml
interface "BaseStream<T, S>" as BaseStream {
    + iterator()
    + spliterator()
    + sequential()
    + parallel()
    + close()
}

interface "Stream<T>" as Stream {
    + filter(Predicate)
    + map(Function)
    + collect(Collector)
    + reduce(BinaryOperator)
}

abstract class "PipelineHelper<P_OUT>" as PipelineHelper {
    + wrapAndCopyInto()
    + wrapSink()
    + copyInto()
}

abstract class "AbstractPipeline<E_IN, E_OUT, S>" as AbstractPipeline {
    - previousStage
    - nextStage
    - sourceStage
    - combinedFlags
    + evaluate(TerminalOp)
    + wrapSink(Sink)
    + copyInto(Sink, Spliterator)
}

abstract class "ReferencePipeline<P_IN, P_OUT>" as ReferencePipeline {
    + filter()
    + map()
    + collect()
}

abstract class "ReferencePipeline.StatelessOp<E_IN, E_OUT>" as StatelessOp {
    # opWrapSink()
}

abstract class "ReferencePipeline.StatefulOp<E_IN, E_OUT>" as StatefulOp {
    # opEvaluateParallel()
}

class "ReferencePipeline.Head<E_IN, E_OUT>" as Head

interface "Sink<T>" as Sink {
    + begin(long)
    + accept(T)
    + end()
    + cancellationRequested()
}

interface "TerminalOp<E_IN, R>" as TerminalOp {
    + evaluateSequential()
    + evaluateParallel()
    + getOpFlags()
}

interface "TerminalSink<T, R>" as TerminalSink

interface "AccumulatingSink<T, R, K>" as AccumulatingSink {
    + combine(K)
}

interface "Collector<T, A, R>" as Collector {
    + supplier()
    + accumulator()
    + combiner()
    + finisher()
    + characteristics()
}

class "Collectors" as Collectors {
    + {static} toList()
    + {static} toSet()
    + {static} groupingBy()
    + {static} reducing()
}

abstract class "ReduceOps.ReduceOp<T, R, S>" as ReduceOp {
    + makeSink()
}

class "ForEachOps.ForEachOp" as ForEachOp
class "FindOps.FindOp" as FindOp
class "MatchOps.MatchOp" as MatchOp

BaseStream <|.. Stream
Stream <|.. ReferencePipeline
PipelineHelper <|-- AbstractPipeline
BaseStream <|.. AbstractPipeline
AbstractPipeline <|-- ReferencePipeline
ReferencePipeline <|-- StatelessOp
ReferencePipeline <|-- StatefulOp
ReferencePipeline <|-- Head
Sink <|.. TerminalSink
AccumulatingSink <|.. TerminalSink

TerminalOp <|.. ReduceOp
TerminalOp <|.. ForEachOp
TerminalOp <|.. FindOp
TerminalOp <|.. MatchOp

TerminalSink <|.. ForEachOp

ReduceOp ..> AccumulatingSink : makeSink() returns S
Collectors ..> Collector : factory methods
Stream ..> Collector : collect(Collector)
Stream ..> TerminalOp : evaluate via ReduceOps / ForEachOps / …
ReduceOp ..> Collector : makeRef(Collector)\nwraps supplier/accumulator/combiner
@enduml
```

Terminal operations are **not** pipeline stages — they are created at evaluation time by factory classes. `collect(Collector)` builds a `ReduceOps.ReduceOp` whose `ReducingSink` implements `AccumulatingSink`: the collector's `supplier` initializes state, `accumulator` accepts each element, and `combiner` merges partial results across parallel workers. `ReferencePipeline` applies the collector's `finisher` after `evaluate` returns. Other terminals use sibling ops: `ForEachOps` (side-effect), `FindOps` (`findFirst` / `findAny`), `MatchOps` (`anyMatch` / `allMatch` / `noneMatch`); `reduce` and `count` also route through `ReduceOps.ReduceOp` with different sinks.

### 3.2 Pipeline stage linking

Each `AbstractPipeline` instance is one **stage**. Stages form a doubly-linked list (`previousStage` / `nextStage`) from source to terminal:

```mermaid
flowchart LR
    Head["ReferencePipeline.Head\n(source spliterator)"]
    Filter["StatelessOp: filter"]
    Map["StatelessOp: map"]
    Terminal["TerminalOp: collect"]

    Head --> Filter --> Map --> Terminal
```

### 3.3 Parallel execution runtime

Every stream parallel task is ultimately a `ForkJoinTask`. `CountedCompleter` extends `ForkJoinTask` and overrides `exec()` to delegate to `compute()`; `AbstractTask` implements that split/fork/leaf logic. A terminal op such as `ReduceOp.evaluateParallel()` constructs the root task and blocks on `invoke()` until the tree completes:

```java
// ReduceOps.java
return new ReduceTask<>(this, helper, spliterator).invoke().get();
```

```plantuml
@startuml
class "ForkJoinPool" as FJP {
    + {static} commonPool()
}

abstract class "ForkJoinTask<V>" as ForkJoinTask {
    + invoke()
    + fork()
    + join()
    # exec()
    + getRawResult()
}

class "CountedCompleter<R>" as CountedCompleter {
    + compute()
    + fork()
    + tryComplete()
    + setPendingCount(n)
    # exec() → compute()
}

abstract class "AbstractTask<P_IN, P_OUT, R, K>" as AbstractTask {
    - spliterator
    - targetSize
    - leftChild
    - rightChild
    - localResult
    + compute()
    + doLeaf()
    + makeChild()
    + onCompletion()
    + getRawResult()
}

abstract class "AbstractShortCircuitTask" as ShortCircuitTask {
    - sharedResult
    - canceled
    + shortCircuit()
}

class "ReduceTask" as ReduceTask {
    + doLeaf()
    + onCompletion()
}

class "FindTask" as FindTask
class "MatchTask" as MatchTask
class "CollectorTask" as CollectorTask
class "SliceTask" as SliceTask

ForkJoinTask <|-- CountedCompleter
CountedCompleter <|-- AbstractTask
AbstractTask <|-- ShortCircuitTask
AbstractTask <|-- ReduceTask
AbstractTask <|-- CollectorTask
ShortCircuitTask <|-- FindTask
ShortCircuitTask <|-- MatchTask
ShortCircuitTask <|-- SliceTask

interface "TerminalOp<E_IN, R>" as TerminalOp {
    + evaluateParallel()
}

interface "AccumulatingSink" as AccumulatingSink {
    + combine()
    + get()
}

ReduceTask --> TerminalOp : evaluateParallel creates root
ReduceTask ..> AccumulatingSink : doLeaf → sink;\nonCompletion → combine
ForkJoinTask ..> FJP : fork() → pool queue;\ncaller thread runs invoke()
@enduml
```

| Task type | Extends | Used for |
|-----------|---------|----------|
| `ReduceTask` | `AbstractTask` | `reduce`, `collect`, `count` |
| `FindTask` | `AbstractShortCircuitTask` | `findFirst`, `findAny` |
| `MatchTask` | `AbstractShortCircuitTask` | `anyMatch`, `allMatch`, `noneMatch` |
| `CollectorTask` | `AbstractTask` | parallel `Nodes.collect` (stateful segment materialization) |
| `SliceTask` | `AbstractShortCircuitTask` | ordered parallel `skip` / `limit` barriers |

Target leaf size ≈ `estimateSize() / (parallelism × 4)` — over-partitioned so idle workers can steal forked tasks. The calling thread runs the root task inline via `invoke()` → `doExec()`; sibling subtasks are `fork()`'d into `ForkJoinPool.commonPool()` for work-stealing. `ReduceTask.doLeaf()` runs the same fused `wrapSink` chain as sequential mode on its sub-spliterator; `onCompletion()` walks up the tree calling `AccumulatingSink.combine()` on sibling partial results.

---

## 4. Implementation Details

### 4.1 Stream creation and intermediate ops

`StreamSupport.stream` wraps a spliterator in `ReferencePipeline.Head` and records source flags. Intermediate methods such as `filter` append a `StatelessOp` stage — they do not process elements:

```java
// StreamSupport.java
public static <T> Stream<T> stream(Spliterator<T> spliterator, boolean parallel) {
    return new ReferencePipeline.Head<>(spliterator,
            StreamOpFlag.fromCharacteristics(spliterator), parallel);
}

// ReferencePipeline.java — filter (representative intermediate op)
return new StatelessOp<>(this, StreamShape.REFERENCE, StreamOpFlag.NOT_SIZED) {
    Sink<P_OUT> opWrapSink(int flags, Sink<P_OUT> sink) {
        return new Sink.ChainedReference<>(sink) {
            public void accept(P_OUT u) {
                if (predicate.test(u)) downstream.accept(u);
            }
        };
    }
};
```

Each new stage links via `previousStage` / `nextStage` and marks upstream `linkedOrConsumed = true`.

### 4.2 The Sink protocol and short-circuit

`Sink<T>` extends `Consumer<T>` with `begin` → `accept` → `end`. At evaluation time `wrapSink` builds a fused chain terminal-inward:

```java
final <P_IN> Sink<P_IN> wrapSink(Sink<E_OUT> sink) {
    for (AbstractPipeline p = AbstractPipeline.this; p.depth > 0; p = p.previousStage)
        sink = p.opWrapSink(p.previousStage.combinedFlags, sink);
    return (Sink<P_IN>) sink;
}
```

Pipeline stages are static **declaration**; sinks drive **execution** in one pass ($O(1)$ intermediate memory).

**Short-circuit.** Ops like `findFirst`, `anyMatch`, `limit` inject `StreamOpFlag.IS_SHORT_CIRCUIT`. Then `copyInto` uses `forEachWithCancel` — polling `cancellationRequested()` before each `tryAdvance` instead of bulk `forEachRemaining`:

```java
do { } while (!(cancelled = sink.cancellationRequested()) && spliterator.tryAdvance(sink));
```

`Sink.ChainedReference` delegates `cancellationRequested()` downstream. Terminal sinks set cancel state in `accept`:

```java
// FindOps — findFirst
public void accept(T value) { if (!hasValue) { hasValue = true; this.value = value; } }
public boolean cancellationRequested() { return hasValue; }

// SliceOps — limit(n)
public boolean cancellationRequested() { return m == 0 || downstream.cancellationRequested(); }
```

Non-short-circuit pipelines never pay the per-element poll. Parallel short-circuit ops use `AbstractShortCircuitTask` to cancel sibling ForkJoin workers once any leaf finds a result.

### 4.3 Terminal evaluation

Every terminal method creates a `TerminalOp` and calls `evaluate`, which consumes the stream and dispatches sequential or parallel:

```java
final <R> R evaluate(TerminalOp<E_OUT, R> terminalOp) {
    linkedOrConsumed = true;
    return isParallel()
           ? terminalOp.evaluateParallel(this, sourceSpliterator(terminalOp.getOpFlags()))
           : terminalOp.evaluateSequential(this, sourceSpliterator(terminalOp.getOpFlags()));
}

final <P_IN> void copyInto(Sink<P_IN> wrappedSink, Spliterator<P_IN> spliterator) {
    if (!StreamOpFlag.SHORT_CIRCUIT.isKnown(getStreamAndOpFlags())) {
        wrappedSink.begin(spliterator.getExactSizeIfKnown());
        spliterator.forEachRemaining(wrappedSink);
        wrappedSink.end();
    } else {
        copyIntoWithCancel(wrappedSink, spliterator);
    }
}
```

Parallel `reduce` / `collect` submit a `ReduceTask` that splits the spliterator, runs `wrapAndCopyInto(makeSink(), chunk)` per leaf, and merges via `AccumulatingSink.combine()` in `onCompletion`.

### 4.4 Parallel execution

`.parallel()` sets `sourceStage.parallel = true` — no threads until a terminal op runs. `AbstractTask` (a `CountedCompleter`) recursively `trySplit`s the spliterator until chunks reach target size ≈ `N / (4 × parallelism)`, then each leaf runs the fused sink chain:

```java
while (sizeEstimate > sizeThreshold && (ls = rs.trySplit()) != null) {
    leftChild = makeChild(ls);
    rightChild = makeChild(rs);
    taskToFork.fork();
}
setLocalResult(doLeaf());  // helper.wrapAndCopyInto(op.makeSink(), spliterator)
```

`ReduceTask.onCompletion` merges sibling partial results via `AccumulatingSink.combine()`. Parallel `collect` with a `CONCURRENT` collector on an unordered stream skips tree merge — workers write into one shared concurrent map.

When **stateful** ops appear (`sorted`, `distinct`, `limit`, …), the pipeline splits into segments (§4.5) instead of one fused split tree.

### 4.5 Parallel segmentation at stateful boundaries

Stateful ops need global input knowledge, so parallel evaluation **materializes barriers** between segments. This runs inside `sourceSpliterator()`, called before the terminal op:

```java
if (isParallel() && hasAnyStateful()) {
    int depth = 1;
    for (AbstractPipeline u = sourceStage, p = sourceStage.nextStage, e = this; u != e; u = p, p = p.nextStage) {
        if (p.opIsStateful()) {
            depth = 0;
            spliterator = p.opEvaluateParallelLazy(u, spliterator);  // u = upstream segment helper
        }
        p.depth = depth++;
        p.combinedFlags = StreamOpFlag.combineOpFlags(p.sourceOrOpFlags, u.combinedFlags);
    }
}
```

**`depth` rewiring.** After preparation, `wrapSink` only includes stages with `depth > 0`. For `parallel().filter().sorted().map().collect()`:

| Stage | `depth` | Role |
|-------|---------|------|
| filter | 1 | consumed inside `sorted.opEvaluateParallel` |
| sorted | 0 | barrier — excluded from terminal `wrapSink` |
| map | 1 | only op in terminal segment |

**Per-op strategies** (all call parallel collect on upstream segment first when materializing):

- **`sorted`** — `helper.evaluate()` → `Node` → `Arrays.parallelSort`
- **`distinct` (ordered)** — parallel collect into `LinkedHashSet`; unordered may use lazy `DistinctSpliterator`
- **`limit/skip`** — cheap `SliceSpliterator` if unordered+subsized; else `SliceTask` full materialization

Example `parallel().filter().sorted().map().collect()`: `sorted` parallel-collects+filters into a `Node`, sorts it, returns a spliterator; terminal `ReduceTask` splits that sorted output and runs only the `map` sink per leaf.

```mermaid
flowchart LR
    subgraph Seg1["Segment 1"]
        S1["source"] --> F1["filter"]
    end
    ST["sorted → Node"]
    subgraph Seg2["Segment 2"]
        M1["map"] --> T1["collect"]
    end
    F1 --> ST --> M1
```

#### Worked example: `parallel().filter().sorted().map().collect(toList())`

Consider a `List<String>` with 10,000 elements. The pipeline stages link as:

`Head → filter(p) → sorted() → map(f) → collect(toList())`

When `collect` runs on the **map** stage, execution happens in **three phases**:

**Phase 1 — `sourceSpliterator()` prepares segments**

`evaluate()` calls `sourceSpliterator()` before `evaluateParallel`. The loop hits the stateful **`sorted`** stage (`p`) with upstream helper **`filter`** (`u`):

```java
// Inside sorted.opEvaluateParallel(filterHelper, listSpliterator)
T[] data = filterHelper.evaluate(spliterator, true, generator).asArray(generator);
Arrays.parallelSort(data, comparator);
return Nodes.node(data).spliterator();
```

What runs here:

1. **`filterHelper.evaluate`** — parallel `Nodes.collect` / `CollectorTask` tree splits the **list spliterator** across ForkJoin workers.
2. Each leaf calls `filterHelper.wrapAndCopyInto(sink, chunk)` — a fused sink chain of **Head → filter only** (`sorted` has `depth = 0`, so it is not in this chain).
3. Partial `Node` trees merge into one flat array of filtered elements.
4. **`Arrays.parallelSort`** sorts the entire array on the common pool.
5. Return value replaces `spliterator` with a **spliterator over the sorted `Node`**.

Then `sourceSpliterator` assigns depths: `sorted.depth = 0`, `map.depth = 1`.

**Phase 2 — terminal `ReduceTask` on segment 2**

```java
new ReduceTask<>(ReduceOps.makeRef(collector), mapStage, sortedNodeSpliterator).invoke();
```

The spliterator now describes **sorted output**, not the original list. `ReduceTask` splits it again:

| Worker | `trySplit` chunk | `wrapSink` chain | Partial result |
|--------|------------------|------------------|----------------|
| W1 | elements 0–2499 | **map(f) → list sink** | `List` fragment A |
| W2 | elements 2500–4999 | **map(f) → list sink** | `List` fragment B |
| … | … | … | … |

Only **`map`** appears in `wrapSink` — `filter` and `sorted` already ran in phase 1.

**Phase 3 — merge**

Internal `ReduceTask` nodes call `onCompletion`: sibling list fragments combine via the collector's combiner until one `List` is returned.

```mermaid
sequenceDiagram
    participant Collect as collect() on map stage
    participant SrcSpl as sourceSpliterator()
    participant Filter as filter (helper u)
    participant Sorted as sorted (stateful p)
    participant FJP as ForkJoinPool
    participant Reduce as ReduceTask

    Collect->>SrcSpl: prepare spliterator
    SrcSpl->>Sorted: opEvaluateParallelLazy(filter, listSpliterator)

    Sorted->>FJP: filterHelper.evaluate — split list
    loop each leaf chunk
        FJP->>Filter: wrapAndCopyInto(filterSink, chunk)
    end
    FJP-->>Sorted: Node of filtered elements
    Sorted->>Sorted: Arrays.parallelSort(node)
    Sorted-->>SrcSpl: spliterator over sorted Node
    SrcSpl->>SrcSpl: sorted.depth=0, map.depth=1

    Collect->>Reduce: evaluateParallel(map, sortedSpliterator)
    loop each leaf chunk
        Reduce->>Reduce: wrapAndCopyInto(mapSink, chunk)
    end
    Reduce->>Reduce: combine partial lists
    Reduce-->>Collect: final List
```

**Contrast — no stateful op:** `parallel().filter().map().collect()` skips phase 1 entirely. One `ReduceTask` splits the **original list spliterator** once; each leaf runs **filter → map → list sink** in a single fused pass.

**Two stateful ops:** `parallel().distinct().sorted().collect()` runs **two barriers** inside `sourceSpliterator`:

1. `distinct.opEvaluateParallelLazy` → `Node` / spliterator of unique elements (ordered: full `LinkedHashSet` materialization).
2. `sorted.opEvaluateParallelLazy` → parallel-collects that output, sorts, returns new spliterator.
3. Terminal `collect` runs on segment 3 only.

Each barrier is a complete parallel pass; memory holds the intermediate `Node` until the next segment finishes.

---
