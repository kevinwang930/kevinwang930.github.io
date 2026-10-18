---
title: "JVM Heap Memory Inspection"
date: 2026-10-18T10:00:00+02:00
categories:
- java
- jvm
- gc
tags:
- jvm
- gc
- heap
keywords:
- jmap
- jstat
- jhsdb
- NMT
---

Inspecting a running JVM heap means attaching to the live process and reading the Java objects it holds. Four JDK tools do that: `jcmd`, `jmap`, `jstat`, and `jhsdb jmap --pid`.

<!--more-->

---

## 1. Overview

The Java heap is the storage `new` draws from. A generational collector splits it into a young generation, Eden and Survivor, and an old generation. Process RSS is larger than that heap: Metaspace, thread stacks, the code cache, and direct buffers sit outside it and are not reclaimed by a young collection.

Four tools attach to that running process. They differ in whether the VM runs the inspection itself, and in whether any object is visited.

| Tool | How it attaches | What it can print |
|------|-----------------|-------------------|
| `jcmd` | A diagnostic command inside the VM | Heap occupancy, a class histogram, an HPROF file, the finalizer queue |
| `jmap` | The attach listener | A class histogram, an HPROF file, the finalizer queue |
| `jstat` | Performance counters | Generation capacity and occupancy, sampled while mutators run |
| `jhsdb jmap --pid` | The serviceability agent, reading the process from outside | A heap summary, a class histogram, an HPROF file, the finalizer queue |

---

## 2. jcmd

`jcmd <pid> <command>` attaches and runs a diagnostic command inside the process. `GC.heap_info` prints heap occupancy. `GC.class_histogram` and `GC.heap_dump` walk objects at a safepoint. `GC.finalizer_info` prints the finalizer queue.

| Command | What it prints |
|---------|----------------|
| `jcmd <pid> GC.heap_info` | Reserved, committed, and used bytes, and the size of each generation. |
| `jcmd <pid> GC.class_histogram` | Instance count and shallow bytes per class, after a full collection. |
| `jcmd <pid> GC.class_histogram -all=true` | The same histogram, including unreachable objects. |
| `jcmd <pid> GC.heap_dump <file>` | HPROF of reachable objects. A full collection runs first. |
| `jcmd <pid> GC.heap_dump -all=true -gz=1 <file>` | HPROF including unreachable objects, gzipped. `-gz` is 1 through 9. `-overwrite=true` replaces an existing file. `-parallel=<n>` is the writer count; `0` or `1` writes on one thread. |
| `jcmd <pid> GC.finalizer_info` | Instances waiting for finalization, counted by class. |

`GC.heap_info` sums heap occupancy, including unreachable objects that the next collection would drop. The histogram's byte column is shallow size: the object's own header and fields. A `byte[]` line and the `String` or cache entry that points at it are separate rows. The HPROF file records every reference. A viewer then computes retained size, the bytes that would become unreachable if one object were removed. That dominator tree is computed by the viewer from the references in the file.

### Inspecting a leak

Take pid `4120`, a service whose heap grows and stays grown after GC. Read occupancy, then the live classes, then the owner.

```text
jcmd 4120 GC.heap_info
```

The first sample reports used 445440K, with Eden 30M, Survivor 5M, and Old 400M. After the service has taken more traffic, and after a histogram has forced a full collection:

```text
jcmd 4120 GC.heap_info
```

Used is 947200K, Eden 20M, Survivor 5M, and Old 900M. The heap committed more memory to hold Old. Eden did not grow. The retained data is in the old generation.

```text
jcmd 4120 GC.class_histogram
```

```text
 num     #instances         #bytes  class name (module)
-------------------------------------------------------
   1:        400000       48000000  [B (java.base@22)
   2:        400000       12800000  com.example.Session
```

A later sample, again after the collection this command requests:

```text
   1:        800000       96000000  [B (java.base@22)
   2:        800000       25600000  com.example.Session
```

`[B` is `byte[]`. Both lines doubled and both survived a full GC, so the arrays and the `Session` objects are reachable. The histogram names those two classes. Write the reachable graph to name the object that points at them:

```text
jcmd 4120 GC.heap_dump /tmp/heap.hprof
```

In the viewer, one `com.example.SessionCache` has a small shallow size and a retained size that covers the `Session` instances and their `byte[]` elements. That cache is the leak: it inserts sessions and never removes them. The `byte[]` row was the bytes; `SessionCache` is the owner.

If the class that survives is also the class in the finalizer queue, the retainer is the queue rather than an application cache:

```text
jcmd 4120 GC.finalizer_info
```

```text
Unreachable instances waiting for finalization
#instances  class name
-----------------------
    800000  com.example.Buffer
```

Those instances are unreachable from application roots and still live, because the finalizer queue is a GC root. `jcmd 4120 GC.run_finalization` runs `System.runFinalization()`. A later `GC.class_histogram` drops the class only after `finalize` has run and a following collection reclaims the instances.

---

## 3. jmap

`jmap` attaches to the running process. `-histo` and `-dump` walk the heap at a safepoint, the same walks as `GC.class_histogram` and `GC.heap_dump`. `-finalizerinfo` forwards to `GC.finalizer_info`. `jmap -histo` and `jmap -dump` include unreachable objects unless `live` is set. `live` requests a full collection first. `all` is the default and keeps garbage.

| Command | What it prints |
|---------|----------------|
| `jmap -histo <pid>` | Histogram of every object, including unreachable ones. |
| `jmap -histo:live <pid>` | Histogram after a full collection. |
| `jmap -histo:live,file=<file>,parallel=<n> <pid>` | The same histogram, written to `<file>`. `all` may replace `live`. |
| `jmap -dump:format=b,file=<file> <pid>` | HPROF of every object, including unreachable ones. |
| `jmap -dump:live,format=b,file=<file>,gz=<level> <pid>` | HPROF after a full collection. `gz` is 1 through 9 and may be omitted. |
| `jmap -finalizerinfo <pid>` | The same report as `GC.finalizer_info`. |

The byte column is shallow size. Retained size comes from a viewer opened on the dump.

### Inspecting a leak

Compare two live histograms. A class that grows in the live set is retained. A class that appears only when `live` is omitted is garbage from the last mutator interval, not a leak.

```text
jmap -histo:live,file=/tmp/h1.txt 4120
```

After the same traffic that filled Old in the `jcmd` reading:

```text
jmap -histo:live,file=/tmp/h2.txt 4120
```

```text
 num     #instances         #bytes  class name (module)
-------------------------------------------------------
   1:        800000       96000000  [B (java.base@22)
   2:        800000       25600000  com.example.Session
```

`/tmp/h1.txt` had half those instances. Both samples already excluded unreachable objects, so the extra `Session` and `byte[]` instances are still rooted. Write the graph of that live set:

```text
jmap -dump:live,format=b,file=/tmp/heap.hprof 4120
```

The viewer shows the same dominator as the `jcmd` dump: `com.example.SessionCache` retains the sessions, and each session retains one `byte[]`. If `jmap -finalizerinfo 4120` prints that same class with a matching instance count, the queue is the root, and the next step is `jcmd 4120 GC.run_finalization` followed by another `-histo:live`.

---

## 4. jstat

`jstat` samples the performance counters the VM exports. The mutators keep running. `<interval>` is milliseconds unless it ends in `s`. `<count>` is how many samples to print; omitted, sampling continues until the JVM or `jstat` exits.

| Command | What it prints |
|---------|----------------|
| `jstat -gc <pid> [<interval> [<count>]]` | Capacity and used bytes of each generation, plus collection counts and times. |
| `jstat -gccapacity <pid>` | Current, minimum, and maximum capacity of each space. |
| `jstat -gcutil <pid>` | Occupancy of each space as a percentage. |
| `jstat -gccause <pid>` | The `-gcutil` columns, plus the cause of the last collection and of a collection in progress. |
| `jstat -gcnew <pid>` | New-generation capacity, occupancy, and collection counts. |
| `jstat -gcnewcapacity <pid>` | New-generation minimum, current, and maximum capacity. |
| `jstat -gcold <pid>` | Old-generation capacity, occupancy, collection counts, and metaspace occupancy. |
| `jstat -gcoldcapacity <pid>` | Old-generation minimum, current, and maximum capacity. |

`O` is old-generation occupancy as a percentage of its current capacity. `OU` is old-generation used bytes, in KB, from `-gc`. `FGC` counts full collections. Eden occupancy oscillates because young collections empty it. Old occupancy that steps up at promotion and stays up after `FGC` increases is data a full collection could not free.

### Inspecting a leak

Sample the percentages every five seconds, six times, on the same pid:

```text
jstat -gcutil 4120 5000 6
```

```text
  S0     S1     E      O      M     CCS      YGC     YGCT     FGC    FGCT     CGC     CGCT       GCT
  0.00  48.00  80.00  41.00  94.10  90.20    120    1.840       2   0.310       3    0.040     2.190
  0.00  52.00  22.00  48.00  94.11  90.20    128    1.960       2   0.310       3    0.040     2.310
  0.00   0.00   8.00  74.00  94.12  90.21    136    2.080       3   0.640       4    0.055     2.775
  0.00  46.00  70.00  76.00  94.12  90.21    144    2.200       3   0.640       4    0.055     2.895
  0.00  50.00  18.00  83.00  94.13  90.22    152    2.320       3   0.640       4    0.055     3.015
  0.00   0.00   5.00  91.00  94.14  90.22    160    2.440       4   0.980       5    0.070     3.490
```

`E` falls at each young collection (`YGC` 120 to 160). `O` rises from 41 to 91. `FGC` goes from 2 to 4. The sample in which `FGC` becomes 3 shows `O` at 74, up from 48 in the previous sample; the sample in which `FGC` becomes 4 shows `O` at 91, up from 83. A full collection ran inside those intervals and the old generation was fuller at the next sample. That is retained data, not a transient Eden spike.

`jstat -gccause 4120` adds `LGCC` and `GCC`, the cause of the last collection and of a collection in progress. A young-collection cause with a climbing `O` is promotion. A full-collection cause followed by an `O` that stays high is the same leak signal with the cause named. The counters do not name the class. The next command is `jcmd 4120 GC.class_histogram` or `jmap -histo:live 4120`.

---

## 5. jhsdb

`jhsdb jmap --pid <pid>` attaches with the serviceability agent. On Linux the agent calls `ptrace(PTRACE_ATTACH)`, which stops the process, and then reads its memory from outside the VM. The histogram and the dump include the objects present at that stop, including unreachable ones. `--heap` prints the heap summary.

| Command | What it prints |
|---------|----------------|
| `jhsdb jmap --heap --pid <pid>` | Heap summary of the live process. |
| `jhsdb jmap --histo --pid <pid>` | Class histogram of the live process. |
| `jhsdb jmap --binaryheap --dumpfile <file> --pid <pid>` | HPROF of the live process. `--gz <level>` (1 through 9) compresses it. |
| `jhsdb jmap --finalizerinfo --pid <pid>` | Instances awaiting finalization. |

### Inspecting a leak

`jcmd` and `jmap` need the VM to reach a safepoint. A process that is alive but stuck, so `jcmd 4120 GC.class_histogram` does not return, can still be read from outside. The agent stops it for the read.

```text
jhsdb jmap --histo --pid 4120
```

```text
 num     #instances         #bytes  class name (module)
-------------------------------------------------------
   1:        800000       96000000  [B (java.base@22)
   2:        800000       25600000  com.example.Session
```

This histogram was taken without a full collection, so unreachable objects are included. A class that also dominated the last successful `jstat` interval, where `O` survived a full GC, is still the candidate. Write the graph while the process is stopped:

```text
jhsdb jmap --binaryheap --dumpfile /tmp/heap.hprof --pid 4120
```

The viewer again names `com.example.SessionCache` as the dominator of the `Session` instances and their arrays. `jhsdb jmap --heap --pid 4120` is the heap summary for the same stop: a large old generation matches the `O` column `jstat` was climbing. `jhsdb jmap --finalizerinfo --pid 4120` is the queue reading when the question is objects waiting on `finalize`. Detach returns the process to execution.

---

## 6. Memory that is not the Java heap

`GC.heap_info` never reports Metaspace, thread stacks, the code cache, or direct `ByteBuffer` storage. Those are native allocations. `VM.native_memory` is the summary, and it is present only when the process was started with `-XX:NativeMemoryTracking=summary` (or `detail`).

```text
jcmd <pid> VM.native_memory summary
jcmd <pid> VM.native_memory detail
jcmd <pid> VM.native_memory summary scale=MB
jcmd <pid> VM.native_memory baseline
jcmd <pid> VM.native_memory summary.diff
jcmd <pid> VM.metaspace
jcmd <pid> VM.metaspace basic
jcmd <pid> VM.classloader_stats
jmap -clstats <pid>
jhsdb jmap --clstats --pid <pid>
jstat -gcmetacapacity <pid>
```

The `Java Heap` line should match the committed size from `GC.heap_info`. `Class` is Metaspace. `Thread` is stacks. `Code` is the code cache. `Internal` includes direct buffers. A process whose RSS grows while `GC.heap_info` stays flat is growing one of those other lines, not the Java heap. `VM.metaspace` and `jstat -gcmetacapacity` are the Metaspace sizes; `VM.classloader_stats` splits those chunks by loader. `basic` prints the metaspace summary without a safepoint. `detail` needs the process started with `-XX:NativeMemoryTracking=detail`. `baseline` stores the current numbers, and `summary.diff` prints the change since that store.

---

## 7. References

- [jcmd](https://docs.oracle.com/en/java/javase/22/docs/specs/man/jcmd.html)
- [jmap](https://docs.oracle.com/en/java/javase/22/docs/specs/man/jmap.html)
- [jstat](https://docs.oracle.com/en/java/javase/22/docs/specs/man/jstat.html)
- [jhsdb](https://docs.oracle.com/en/java/javase/22/docs/specs/man/jhsdb.html)
- [Native Memory Tracking](https://docs.oracle.com/en/java/javase/22/vm/native-memory-tracking.html)
