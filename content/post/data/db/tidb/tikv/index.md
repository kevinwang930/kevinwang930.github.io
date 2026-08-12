---
title: "TiKV : Multi-Raft Regions, peer Raft, and writes (MVCC / 2PC)"
date: 2026-08-08T16:00:00+02:00
categories:
- data
- db
- tidb
tags:
- data
- db
- tidb
keywords:
- tikv
- raft-rs
#thumbnailImage: //example.com/image.jpg
---
**TiKV** is the distributed row store: one sorted keyspace, many **Regions** (each a Raft group), **MVCC** in RocksDB, and Raft-backed apply for every durable write.
<!--more-->

---

## 1. Overview

TiKV is a distributed transactional key-value store. Externally TiDB presents **one globally sorted keyspace**. Internally that map is cut into **Regions**—half-open key ranges `[startKey, endKey)`—managed by **PD** and served by **TiKV store** processes. Each Region is replicated as an independent **Raft** group (default **three peers** on three different stores). Clients (typically TiDB via client-go) send Get / Prewrite / Commit / Coprocessor RPCs to the Region’s **leader**; followers replicate Raft logs. Durable user state is **MVCC** in RocksDB (`lock` / `write` / `default`).

**Common production layouts.** A starter deployment often runs **three TiKV stores** so each Region’s default RF=3 peers can sit on different machines. Scaling for capacity or QPS adds more TiKV stores: PD spreads **more Regions** across them; it does not add extra copies of every Region unless `max-replicas` changes. On disk, a Region (and thus each peer’s data for that Region) is sized around **`region-split-size = 256 MiB`** by default (96 MiB on older releases) and splits near **`region-max-size ≈ 384 MiB`**. A production **TiKV store** data disk is commonly kept within about **1.5 TB (regular SSD) to 2–4 TB (PCIe/NVMe)**, with usage under ~80%, so peer counts stay manageable as capacity grows. If one store or AZ fails, Regions that still have a **majority (2/3)** can elect and commit; the minority side cannot.

| Piece | In TiKV |
|-------|---------|
| **Store** | One TiKV process; many Region peers |
| **Region peer** | One Raft group member for a key range |
| **Leader** | Accepts KV RPCs; proposes to the Raft log |
| **kvdb / raftdb** | User MVCC vs Raft HardState + log |


![TiKV store process architecture](images/tikv-store-architecture.svg)

Top → bottom inside one store:

1. **gRPC** — Get, Prewrite, Commit, Coprocessor, …  
2. **Scheduler / latches** — per-key conflict control before propose  
3. **raftstore** — FSM per peer; Multi-Raft on this machine  
4. **Apply** — committed entries → MVCC mutations  
5. **kvdb + raftdb** — two RocksDB instances  

| Engine | Holds |
|--------|-------|
| **raftdb** | Raft HardState and Raft log per peer (consensus machinery) |
| **kvdb** | User MVCC (`lock`, `write`, `default` CFs) after apply |

Client KV RPCs target the **Region leader**. Followers receive Raft messages from other TiKV stores. PD heartbeats carry store/Region meta; they do not carry row values.

### Process structure

TiKV is one OS process. Its in-memory layout is a **composition of structs**: ownership (`struct` fields) plus shared handles (`Arc` / `Clone` engine wrappers).


- **TikvServer** — process root: wires gRPC, engines, PD client, and the Multi-Raft system.
- **Server (gRPC)** — accepts client KV RPCs (Get, Prewrite, Commit, Coprocessor, …) and peer Raft messages from other TiKV stores.
- **Storage** / **TxnScheduler** — turns an RPC into transactional work: latches for key conflicts, prepare read or write batch, then hand off to the engine.
- **RaftKv** — Storage’s engine facade: **writes** go to `RaftRouter` as proposals; **local reads** can use the kv engine / snapshot path.
- **Engines** — shared disk handles: `kv` (user MVCC) and `raft` (HardState + Raft log).
- **StoreMeta** — in-memory Region map and key-range index for this store (which `region_id` owns which keys).
- **MultiRaftServer** / **RaftBatchSystem** — runs peer and apply pollers; owns the routers that deliver messages to FSMs.
- **RaftRouter** — `region_id` → mailbox of a **PeerFsm**; entry point for propose and Raft `step`.
- **PeerFsm** / **Peer** — one local replica of one Region: proposals, lease, and the Raft group.
- **RawNode** — raft-rs facade (`raft: Raft` is the consensus state machine); opaque `Entry.data` until apply.
- **PeerStorage** — implements raft Storage: persist / load HardState and log entries via `Engines.raft`.
- **ApplyFsm** / **ApplyDelegate** — same `region_id`; applies committed entries into `Engines.kv` (MVCC Puts/Deletes).

```plantuml
@startuml

struct TikvServer {
  core : TikvServerCore
  router : RaftRouter
  system : Option~RaftBatchSystem~
  engines : Option~TikvEngines~
  servers : Option~Servers~
  pd_client : Arc~PdClient~
  concurrency_manager : ConcurrencyManager
}

struct Servers {
  server : Server
  raft_server : MultiRaftServer
  lock_mgr : LockManager
  importer : Arc~SstImporter~
}

struct TikvEngines {
  engines : Engines
  store_meta : Arc~Mutex~StoreMeta~~
  engine : RaftKv
}

struct Engines {
  kv : KvEngine
  raft : RaftEngine
}

struct StoreMeta {
  store_id : Option~u64~
  region_ranges : BTreeMap~end_key, region_id~
  regions : HashMap~region_id, Region~
  readers : HashMap~region_id, ReadDelegate~
}

struct Storage {
  engine : RaftKv
  sched : TxnScheduler
  read_pool : ReadPoolHandle
  concurrency_manager : ConcurrencyManager
}

struct RaftKv {
  router : RaftRouter
  engine : KvEngine
}

struct MultiRaftServer {
  store : metapb.Store
  system : RaftBatchSystem
  pd_client : Arc~PdClient~
}

struct RaftBatchSystem {
  system : BatchSystem~PeerFsm, StoreFsm~
  router : RaftRouter
  apply_router : ApplyRouter
  apply_system : ApplyBatchSystem
}

struct RaftRouter {
  normals : DashMap~region_id, Mailbox~PeerFsm~~
  control_box : Mailbox~StoreFsm~
}

struct PeerFsm {
  peer : Peer
  receiver : Receiver~PeerMsg~
  mailbox : Option~BasicMailbox~
  has_ready : bool
}

struct Peer {
  region_id : u64
  peer : metapb.Peer
  raft_group : RawNode~PeerStorage~
  proposals : ProposalQueue
  leader_lease : Lease
}

struct RawNode {
  raft : Raft
  storage : PeerStorage
}

struct PeerStorage {
  engines : Engines
  region : Region
  peer_id : u64
  entry_storage : EntryStorage
}

struct ApplyBatchSystem {
  normals : DashMap~region_id, Mailbox~ApplyFsm~~
}

struct ApplyFsm {
  delegate : ApplyDelegate
  receiver : Receiver~Msg~
}

struct ApplyDelegate {
  region : Region
  peer : metapb.Peer
  term : u64
  apply_state : RaftApplyState
}

TikvServer *-- Servers
TikvServer *-- TikvEngines
TikvServer o-- RaftRouter : clone handle
TikvServer o-- RaftBatchSystem : moved into MultiRaftServer

Servers *-- MultiRaftServer
Servers o-- "Server (gRPC)"

TikvEngines *-- Engines
TikvEngines *-- RaftKv
TikvEngines o-- StoreMeta : Arc

MultiRaftServer *-- RaftBatchSystem
RaftBatchSystem *-- RaftRouter
RaftBatchSystem *-- ApplyBatchSystem

Storage *-- RaftKv
RaftKv o-- RaftRouter
RaftKv o-- Engines : kv handle

RaftRouter "1" o-- "N" PeerFsm : region_id mailbox
ApplyBatchSystem "1" o-- "N" ApplyFsm : region_id mailbox

PeerFsm *-- Peer
Peer *-- RawNode : raft_group
RawNode *-- PeerStorage
PeerStorage o-- Engines : shared

ApplyFsm *-- ApplyDelegate

PeerFsm .. ApplyFsm : same region_id

@enduml
```

**How an RPC enters.** Client (TiDB) opens gRPC to this store’s **Server**. The handler builds a `Storage` command (e.g. Prewrite or Get). `TxnScheduler` runs it under latches. The command uses **RaftKv**, which already knows the target `region_id` from the request context (filled earlier by Region cache / PD locate on the client).

**How a write becomes durable.** On the Region **leader**, `RaftKv` asks `RaftRouter` to deliver a `RaftCmdRequest` to that Region’s **Peer**. After `propose`, the path is the Ready loop—not an immediate kvdb write:

1. **Propose** — the Peer serializes the command into opaque bytes and calls `RawNode::propose`, which appends a log **Entry** in memory inside `Raft` / `RaftLog`.
2. **Ready (local persist)** — `has_ready()` yields a **Ready**: new log entries (and often HardState) must be written to **raftdb** first.
3. **Replicate** — the same Ready carries outbound **`MsgAppend`** messages; the leader sends them to followers. Each follower `step`s, persists its own raftdb copy, and acks.
4. **Commit** — when a **majority** has that entry durable, raft-rs advances `committed`; the next Ready exposes it in `committed_entries`.
5. **Apply** — the Peer hands those entries to **ApplyFsm**, which decodes `Entry.data` and writes MVCC into **kvdb**.
6. **RPC success** — only after apply does the client write RPC return. Followers apply the same committed entries on their ApplyFsm; they never accept the client write (`NotLeader`).

```text
gRPC write (Prewrite / Commit / …)
  → Storage / TxnScheduler (latch, build Modify batch)
  → RaftKv → RaftRouter → PeerFsm / Peer
  → RawNode.propose          (in-memory Entry)
  → Ready: persist entries → raftdb
  → Ready: send MsgAppend → followers (they persist + ack)
  → majority → committed_entries
  → ApplyFsm → kvdb MVCC
  → RPC response
```

**How a query (read) works.** Point Gets and snapshot reads still enter via gRPC → **Storage**. If the peer is leader and the lease is valid, RaftKv / local reader can serve from a snapshot of **kvdb** without proposing a new log entry (stale or follower reads use other rules: read index or replica read). Coprocessor scans are leader-side reads over the same MVCC. Reads do not change raftdb; they observe state already applied to kvdb.

```text
gRPC read (Get / Coprocessor / …)
  → Storage (snapshot / read pool)
  → RaftKv / local reader → kvdb (MVCC)
  → RPC response
```

**How Raft between stores works.** Another TiKV’s Raft messages (vote, append, heartbeat) hit gRPC as Raft traffic, not as KV commands. The store routes them by `region_id` into the matching **PeerFsm**, which calls `RawNode::step`. Ready then updates **raftdb** and may send more messages or hand committed entries to **ApplyFsm**—the same Ready/apply machinery as a local propose, without going through `Storage`.

```text
peer Raft RPC (MsgAppend / MsgRequestVote / …)
  → RaftRouter → PeerFsm
  → RawNode.step → Ready → raftdb / outbound Messages
  → committed entries → ApplyFsm → kvdb
```

Many Region peers share one `Engines` pair; each peer has its own `RawNode` and apply delegate. Peer Raft is §2; write preparation, MVCC, and 2PC are §3.

## 2. Multi-Raft

**Multi-Raft** means TiKV runs **many Raft groups**, not one: **PD** splits the keyspace into Regions; **each Region is one Raft group** (default three peers on three stores). A **TiKV store** hosts **many peers**—one local replica for each Region PD placed on that machine. The same store can be leader for some Regions and follower for others; leadership is per Region.

![Multi-Raft: PD ranges, many Region peers per TiKV store](images/tikv-multi-raft-peers.svg)

Peers share one process (`TikvServer`: gRPC, `MultiRaftServer`, `Engines`) so TiKV need not open a RocksDB per Region. Consensus stays independent: R1’s election and log progress do not block R2. `RaftRouter` routes work by `region_id` to each `PeerFsm`. Clients send KV RPCs only to that Region’s **leader**.

### 2.1 Peer Raft protocol (RawNode → kvdb)

Each Region **Peer** owns one raft-rs **`RawNode`** (`Peer.raft_group: RawNode<PeerStorage>`). This subsection is the full protocol path on one peer: inputs into the node (including election via `tick` / `MsgHup`), **Ready** handling, **raftdb** durability and replication, then **ApplyFsm** writing user state into **kvdb**. **`Message`** layout is §2.2; **`RaftLog` / `Entry` / `Unstable`** are §2.3; MVCC / 2PC are §3.

**`RawNode.raft`: the consensus engine.** `RawNode` is a thin facade around **`raft: Raft`**. `Raft` holds peer `id`, `term` / `vote`, `StateRole`, timers, outbound `msgs`, follower progress, and `RaftLog` (committed index + `PeerStorage`). `tick` / `step` / `propose` mostly forward into that field; `RawNode` then diffs SoftState / HardState to emit a **`Ready`** for the store.

```plantuml
@startuml


struct PeerFsm {
  peer : Peer
  has_ready : bool
}

struct Peer {
  region_id : u64
  raft_group : RawNode
  proposals : ProposalQueue
}

struct RawNode {
  raft : Raft
  prev_ss : SoftState
  prev_hs : HardState
  --
  has_ready() : bool
  ready() : Ready
}

struct Raft {
  id : u64
  term : u64
  vote : u64
  state : StateRole
  msgs : Message list
  raft_log : RaftLog
}

struct SoftState {
  leader_id : u64
  raft_state : StateRole
}

struct HardState {
  term : u64
  vote : u64
  commit : u64
}

struct RaftLog {
  store : PeerStorage
  unstable : Unstable
  committed : u64
  applied : u64
}

struct Unstable {
  entries : Entry list
  offset : u64
  snapshot : Snapshot optional
}

struct PeerStorage {
  engines : Engines
  region : Region
}

struct Ready {
  number : u64
  ss : SoftState optional
  hs : HardState optional
  entries : Entry list
  messages : Message list
  committed_entries : Entry list
  must_sync : bool
}

struct ApplyFsm {
  delegate : ApplyDelegate
}

PeerFsm *-- Peer
Peer *-- RawNode : raft_group
RawNode *-- Raft
RawNode o-- SoftState : prev_ss
RawNode o-- HardState : prev_hs
RawNode .. Ready : ready()
PeerFsm .. RawNode : has_ready flag then has_ready()
Raft *-- RaftLog
RaftLog *-- Unstable : unstable
RaftLog o-- PeerStorage : store
PeerStorage o-- Engines : raft + kv
Peer .. ApplyFsm : Msg::Apply same region_id
Ready o-- SoftState : ss
Ready o-- HardState : hs
Ready .. Unstable : Ready.entries from unstable
Ready .. PeerStorage : persist hs + entries
Ready .. ApplyFsm : committed_entries

@enduml
```

`PeerFsm.has_ready` is TiKV’s poll batching flag (set after tick / step / propose). `RawNode::has_ready()` is raft-rs’s real check against `prev_ss` / `prev_hs`, `unstable`, and `msgs`; `ready()` then materializes the **`Ready`** value the store must persist and send. `RaftLog.store` vs `unstable` is detailed in §2.3.


#### Three Raft inputs: `tick`, `step`, `propose`

Everything that moves a peer’s consensus state enters `RawNode` through one of three calls. All three eventually drive **`Raft::step`** (tick synthesizes local messages; propose wraps a `MsgPropose`). TiKV’s Peer poller invokes them; afterward the same **Ready** path runs.

| Call | Who invokes it (TiKV) | Role |
|------|------------------------|------|
| **`tick`** | Peer base-tick (`on_raft_base_tick` → `raft_group.tick`) | Advance the logical clock: election timeout or leader heartbeat |
| **`step`** | Peer Raft RPC (`Peer::step`) and local msgs from tick/propose | Apply one `Message`; update term, role, log, outbound msgs |
| **`propose`** | Leader write path (`Peer::propose` → `raft_group.propose`) | Append opaque client bytes as a new log `Entry` (Leader only) |

##### `tick` — timers

`tick` advances Raft’s **logical clock** by one unit. The library does not read wall time; TiKV’s peer base-tick must call `RawNode::tick` on a fixed interval. What a tick does depends on `StateRole`: as **Follower**, **PreCandidate**, or **Candidate**, successive ticks accumulate `election_elapsed` until the randomized election timeout fires, at which point the peer injects a local `MsgHup` and campaigns; as **Leader**, ticks accumulate `heartbeat_elapsed` (and optionally run a quorum check) and inject `MsgBeat` so followers keep resetting their election timers. A tick therefore either starts or sustains leadership—it never itself appends client log entries.

**Implementation.** `RawNode::tick` forwards to `Raft::tick`, which branches on role:

```rust
// RawNode
pub fn tick(&mut self) -> bool {
    self.raft.tick()
}

// Raft
pub fn tick(&mut self) -> bool {
    match self.state {
        StateRole::Follower | StateRole::PreCandidate | StateRole::Candidate => {
            self.tick_election()
        }
        StateRole::Leader => self.tick_heartbeat(),
    }
}
```

```rust
// Follower / Candidate: election timeout → campaign
pub fn tick_election(&mut self) -> bool {
    self.election_elapsed += 1;
    if !self.pass_election_timeout() || !self.promotable {
        return false;
    }
    self.election_elapsed = 0;
    let m = new_message(INVALID_ID, MessageType::MsgHup, Some(self.id));
    let _ = self.step(m);   // becomes Candidate, sends MsgRequestVote
    true
}

// Leader: heartbeat timeout → bcast heartbeat
fn tick_heartbeat(&mut self) -> bool {
    self.heartbeat_elapsed += 1;
    // …
    if self.heartbeat_elapsed >= self.heartbeat_timeout {
        self.heartbeat_elapsed = 0;
        let m = new_message(INVALID_ID, MessageType::MsgBeat, Some(self.id));
        let _ = self.step(m);   // step_leader → bcast_heartbeat
    }
    // …
}
```

TiKV schedules a per-peer Raft tick; when it fires, `has_ready` may become true so heartbeats or vote messages leave via Ready.

##### `step` — network (and local) messages

`step` is the **single transition function** of the consensus state machine: it consumes one `Message` and may update `term`, `vote`, `StateRole`, the Raft log, follower progress, and the outbound `msgs` queue. Network RPCs from other peers (`MsgAppend`, `MsgAppendResponse`, `MsgHeartbeat`, `MsgRequestVote`, …) enter through `RawNode::step` → `Raft::step`. Local control messages synthesized by `tick` or `propose` (`MsgHup`, `MsgBeat`, `MsgPropose`) call `Raft::step` directly. Every meaningful role change and almost every log mutation is the result of some `step`; Ready only reports what `step` (or a preceding tick/propose that stepped) already changed.

**Implementation.** `RawNode::step` rejects unexpected local message types from the network, then calls `Raft::step`:

```rust
// Peer — after gRPC delivers a Raft Message for this region_id
self.raft_group.step(m)?;

// RawNode::step
pub fn step(&mut self, m: Message) -> Result<()> {
    if is_local_msg(m.get_msg_type()) {
        return Err(Error::StepLocalMsg);
    }
    // …
    self.raft.step(m)
}
```

`Raft::step` has two phases: **term gate**, then **message / role dispatch**.

**1. Term gate** — compare `m.term` to `self.term` before interpreting the payload:

```rust
pub fn step(&mut self, m: Message) -> Result<()> {
    if m.term == 0 {
        // local message (MsgHup / MsgBeat / MsgPropose, …)
    } else if m.term > self.term {
        // … PreVote quirks: may ignore vote while lease valid; may not bump term …
        if m.get_msg_type() == MessageType::MsgAppend
            || m.get_msg_type() == MessageType::MsgHeartbeat
            || m.get_msg_type() == MessageType::MsgSnapshot
        {
            self.become_follower(m.term, m.from);
        } else if /* not a PreVote special case */ {
            self.become_follower(m.term, INVALID_ID);
        }
    } else if m.term < self.term {
        // stale leader/candidate: often reply MsgAppendResponse so they learn
        // the newer term, then return without applying the old message
        // …
        return Ok(());
    }
    // … continue below …
```

**2. Dispatch** — `MsgHup` / votes are handled here; everything else goes to the role-specific stepper:

```rust
    match m.get_msg_type() {
        MessageType::MsgHup => self.hup(false),  // → become_candidate / campaign
        MessageType::MsgRequestVote | MessageType::MsgRequestPreVote => {
            // grant or reject; maybe set self.vote = m.from
            // …
        }
        _ => match self.state {
            StateRole::PreCandidate | StateRole::Candidate => self.step_candidate(m)?,
            StateRole::Follower => self.step_follower(m)?,
            StateRole::Leader => self.step_leader(m)?,
        },
    }
    Ok(())
}
```

**`step_leader`** (selected arms) — heartbeats, quorum check, client proposes:

```rust
fn step_leader(&mut self, mut m: Message) -> Result<()> {
    match m.get_msg_type() {
        MessageType::MsgBeat => {
            self.bcast_heartbeat();
            return Ok(());
        }
        MessageType::MsgCheckQuorum => {
            if !self.check_quorum_active() {
                let term = self.term;
                self.become_follower(term, INVALID_ID);  // Leader → Follower
            }
            return Ok(());
        }
        MessageType::MsgPropose => {
            // … reject if not in config / transfer in progress …
            if !self.append_entry(m.mut_entries()) {
                return Err(Error::ProposalDropped);
            }
            self.bcast_append();   // queue MsgAppend to followers
            return Ok(());
        }
        // MsgAppendResponse → update progress, maybe_commit, …
        _ => { /* … */ }
    }
}
```

**`step_follower`** (selected arms) — reset election timer; append or forward proposes:

```rust
fn step_follower(&mut self, mut m: Message) -> Result<()> {
    match m.get_msg_type() {
        MessageType::MsgPropose => {
            // forward to leader_id (or drop) — follower does not append as leader
            m.to = self.leader_id;
            self.r.send(m, &mut self.msgs);
        }
        MessageType::MsgAppend => {
            self.election_elapsed = 0;
            self.leader_id = m.from;
            self.handle_append_entries(&m);  // match log, append, reply
        }
        MessageType::MsgHeartbeat => {
            self.election_elapsed = 0;
            self.leader_id = m.from;
            self.handle_heartbeat(m);
        }
        // …
        _ => {}
    }
}
```

Local messages that **tick** injects call **`Raft::step` directly** (not `RawNode::step`), so `MsgHup` / `MsgBeat` are not rejected as `StepLocalMsg`.

##### `propose` — client log entries

`propose` is how a **Leader** turns a client write into a Raft log entry. TiKV passes opaque bytes—typically a serialized `RaftCmdRequest`—plus an optional context; `RawNode::propose` wraps them as a local `MsgPropose` and `Raft::step`s that message. On the leader, `step_leader` assigns `term`/`index`, appends to `RaftLog`, and queues `MsgAppend` for followers. On a non-leader, the same `MsgPropose` is forwarded or dropped (`NotLeader` / `ProposalDropped`); followers never treat propose as authority to grow the log themselves. Propose does not change `StateRole`: it only extends the log when the peer already is Leader, then relies on the shared Ready path for raftdb persistence, replication, and later apply.

**Implementation.** `RawNode::propose` builds a local `MsgPropose` and steps it; there is no separate propose engine:

```rust
// Peer::propose_normal — after req.write_to_bytes()
self.raft_group.propose(ctx.to_vec(), data)?;

// RawNode::propose
pub fn propose(&mut self, context: impl Into<Bytes>, data: impl Into<Bytes>) -> Result<()> {
    let mut m = Message::default();
    m.set_msg_type(MessageType::MsgPropose);
    m.from = self.raft.id;
    let mut e = Entry::default();
    e.data = data.into();       // RaftCmdRequest bytes
    e.context = context.into();
    m.set_entries(vec![e].into());
    self.raft.step(m)           // → step_leader MsgPropose
}
```

On the leader, `step_leader` accepts `MsgPropose`, appends into `RaftLog`, then broadcasts:

```rust
// Raft::step_leader
MessageType::MsgPropose => {
    if m.entries.is_empty() {
        fatal!(self.logger, "stepped empty MsgProp");
    }
    // drop if removed from config or leadership transfer in progress …
    if !self.append_entry(m.mut_entries()) {
        return Err(Error::ProposalDropped);  // e.g. uncommitted size limit
    }
    self.bcast_append();  // queue MsgAppend for followers
    return Ok(());
}
```

**Append into `RaftLog`.** `append_entry` stamps the leader’s current term and the next indexes, then pushes the slice onto **`RaftLog.unstable`** (in memory only). Persistence to **raftdb** happens later when Ready exposes those entries (§2.1 Ready; log layout §2.3):

```rust
self.raft_log.append(es);  // unstable.truncate_and_append — see §2.3
```

```text
MsgPropose { entries: [Entry { data, context, term:0, index:0 }] }
  → append_entry: set term/index → RaftLog.unstable
  → bcast_append: msgs += MsgAppend(…)
  → Ready.entries = unstable slice → PeerStorage → raftdb
```

`Entry.data` stays opaque inside raft-rs: no CF names, no MVCC decode.

```text
tick  → (MsgHup | MsgBeat) → Raft::step → maybe Ready (votes / heartbeats)
step  → Message from peer  → Raft::step → maybe Ready (log / HardState / msgs)
propose → MsgPropose       → Raft::step → Ready (entries + MsgAppend)
         └──────── all three share the Ready → raftdb / apply path below
```

#### State machine: roles, inputs, Ready

Raft has two layers that change together: **`StateRole`** (SoftState: Follower / PreCandidate / Candidate / Leader) and the store’s **Ready handling** (persist / send / apply / advance). Role changes are triggered by `tick` and `step`; `propose` does not change role—it only appends on a Leader. After any input, SoftState / HardState / log / `msgs` deltas surface as **Ready**.

**Role transitions** (`Raft.state` / SoftState `raft_state`):

```plantuml
@startuml
hide empty description
skinparam state {
  BackgroundColor<<leader>> #E8F5E9
  BackgroundColor<<cand>> #FFF8E1
  BackgroundColor<<fol>> #E3F2FD
}

state "Follower" as F <<fol>>
state "PreCandidate\n(pre-vote on)" as P <<cand>>
state "Candidate" as C <<cand>>
state "Leader" as L <<leader>>

[*] --> F : bootstrap / restart\n(load HardState)

F --> P : tick election timeout\n(pre_vote) / MsgHup dry-run
F --> C : tick election timeout\n(no pre_vote) / MsgHup\n(term++)
P --> C : pre-vote majority\nthen real campaign (term++)
P --> F : pre-vote rejected /\nhear valid leader (higher or current term)

C --> L : majority MsgRequestVoteResponse\n(granted) → become_leader
C --> C : election timeout again\n(term++; new MsgRequestVote)
C --> F : step: higher Message.term /\nAppend or Heartbeat from leader /\nlose vote

L --> F : step: Message.term > currentTerm\n(become_follower) /\ntick: MsgCheckQuorum fails

F --> F : step MsgAppend / MsgHeartbeat\n(same or lower ok path;\nreset election_elapsed)
L --> L : tick MsgBeat (heartbeat) /\nstep MsgAppendResponse /\npropose MsgPropose\n(role unchanged)

@enduml
```

| From → To | Trigger | What runs |
|-----------|---------|-----------|
| Follower → Candidate (or PreCandidate) | **`tick`** election timeout → `MsgHup` | `become_candidate` / `become_pre_candidate`; broadcast votes |
| Candidate → Leader | **`step`** majority vote grants | `become_leader`; SoftState leader_id = self |
| Any → Follower | **`step`** higher `Message.term`, or Append/Heartbeat from a valid leader | `become_follower`; clear leadership |
| Leader → Follower | Higher term, or **`tick`** quorum check fail | Step down |
| Leader → Leader | **`propose`**, **`tick`** heartbeat, append responses | Log / msgs change; **role stays Leader** |

**Ready cycle** (store side; same for every input that dirties the node):

```plantuml
@startuml
hide empty description

state "Idle\n(no pending Ready)" as Idle
state "Input\ntick / step / propose" as In
state "Raft updated\n(role, term, log, msgs)" as Upd
state "has_ready?" as HR <<choice>>
state "Take Ready" as Take
state "Persist\nHardState + entries\n→ raftdb" as Pers
state "Send messages\n(votes, Append, …)" as Send
state "Schedule apply\ncommitted_entries\n→ ApplyFsm → kvdb" as App
state "advance / light apply" as Adv

[*] --> Idle
Idle --> In : Peer poller / RPC / write path
In --> Upd : Raft::tick or Raft::step
Upd --> HR
HR --> Idle : false
HR --> Take : true
Take --> Pers
Take --> Send
Take --> App
Pers --> Adv
Send --> Adv
App --> Adv
Adv --> Idle : ready handled;\nprev_ss / prev_hs updated

note right of In
  propose only accepted
  when state == Leader
  else NotLeader / drop
end note

note right of Take
  Ready may carry:
  ss SoftState (role change)
  hs HardState (term/vote/commit)
  entries, messages,
  committed_entries
end note
@enduml
```

```text
                    ┌─────────────────────────────────────────┐
  tick / step /     │  StateRole: Follower ⇄ Candidate ⇄ Leader │
  propose ─────────►│       SoftState changes when role moves   │
                    └───────────────┬─────────────────────────┘
                                    │ has_ready()
                                    ▼
                         Ready { ss?, hs?, entries?, messages?,
                                 committed_entries? }
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
         raftdb persist        send Messages         ApplyFsm → kvdb
              └─────────────────────┴─────────────────────┘
                                    ▼
                              advance → Idle
```

So: **`tick` / `step` drive role transfers** (including election); **`propose` drives log growth on the Leader**; **Ready** is how every transfer and log update is observed and made durable by TiKV. `Message` fields are §2.2; log layout is §2.3.

#### Ready: when it fires, and how unstable becomes durable

**Propose does not write raftdb.** After `MsgPropose`, the new `Entry` lives only in **`RaftLog.unstable`**, and `bcast_append` only appends **`MsgAppend`** into **`Raft.msgs`**—both in memory. SoftState / HardState may also differ from `RawNode`’s remembered `prev_ss` / `prev_hs`. Nothing is durable until the Peer drains a **Ready**.

**When Ready is triggered.** TiKV does not call `RawNode::has_ready` on every message inline. The peer FSM sets a local flag after inputs that may dirty Raft; at the **end of the poll**, it drains Ready if that flag is set.

After **tick** / **step** / **propose**, mark the peer dirty:

```rust
// tick (on_raft_base_tick)
if self.fsm.peer.raft_group.tick() {
    self.fsm.has_ready = true;
}

// step (inbound Raft Message for this region)
self.fsm.peer.step(self.ctx, msg.take_message())?;
// …
self.fsm.has_ready = true;

// propose (RaftCmdRequest on the leader)
if self.fsm.peer.propose(self.ctx, cb, msg, resp, diskfullopt) {
    self.fsm.has_ready = true;
}
```

End of the peer poll cycle — only then call into raft-rs:

```rust
// PeerFsmDelegate::collect_ready — after handle_msgs in this poll
pub fn collect_ready(&mut self) -> bool {
    let has_ready = self.fsm.has_ready;
    self.fsm.has_ready = false;
    if !has_ready || self.fsm.stopped {
        return false;
    }
    let res = self.fsm.peer.handle_raft_ready_append(self.ctx);
    // …
}

// Peer::handle_raft_ready_append
if !self.raft_group.has_ready() {
    return None;  // flag was optimistic; nothing to drain
}
let mut ready = self.raft_group.ready();
```

`RawNode::has_ready()` is the precise check: true when any in-memory delta exists:

```rust
pub fn has_ready(&self) -> bool {
    let raft = &self.raft;
    if !raft.msgs.is_empty() { return true; }                    // outbound Messages
    if raft.soft_state() != self.prev_ss { return true; }        // role / leader_id
    if raft.hard_state() != self.prev_hs { return true; }        // term / vote / commit
    if !raft.raft_log.unstable_entries().is_empty() { return true; } // unstable log
    // … snapshot or newly commit-able entries since commit_since_index …
    false
}
```

```text
tick / step / propose
  → PeerFsm.has_ready = true          (batching flag)
  → (more msgs in same poll…)
  → collect_ready()
       → handle_raft_ready_append()
            → RawNode::has_ready()?   (real check)
            → RawNode::ready()
```

So a successful **propose** sets the FSM flag because **`unstable` is non-empty** and **`msgs` holds `MsgAppend`**; `has_ready()` confirms that before `ready()` is taken.

**What `ready()` packages.** `RawNode::ready()` snapshots those deltas into a `Ready` the store must handle before further `step` / `propose`:

```rust
pub fn ready(&mut self) -> Ready {
    // …
    if ss != self.prev_ss { rd.ss = Some(ss); }
    if hs != self.prev_hs { rd.hs = Some(hs); }
    rd.entries = raft.raft_log.unstable_entries().to_vec(); // copy from Unstable
    // Leader: messages may be sent before/while persisting (concurrent replication)
    // Follower: messages that must wait for persist go on the persisted path
    rd.light = self.gen_light_ready(); // messages + committed_entries
    rd
}
```

| Ready field | Comes from (in memory) | Peer must |
|-------------|------------------------|-----------|
| `entries` | `RaftLog.unstable.entries` | Persist to **raftdb** (`PeerStorage` / write worker) |
| `hs` | HardState delta vs `prev_hs` | Persist to **raftdb** |
| `ss` | SoftState delta vs `prev_ss` | Update lease / role bookkeeping (not raftdb log) |
| `messages` | `Raft.msgs` (e.g. `MsgAppend`) | Send to other TiKV peers |
| `committed_entries` | committed but not yet applied slice | Schedule **ApplyFsm** → kvdb |

```text
propose / step / tick
  → only memory: Unstable + msgs (+ maybe term/role)
  → has_ready() == true
  → ready()
       Ready.entries  ← unstable_entries()
       Ready.messages ← raft.msgs
       Ready.hs / ss  ← HardState / SoftState deltas
  → Peer:
       persist entries + hs → raftdb
       send messages → network
       committed_entries → ApplyFsm
  → advance / on_persist_*  (stable unstable; update prev_ss / prev_hs)
```

```rust
if !self.raft_group.has_ready() { return None; }
let mut ready = self.raft_group.ready();

if !ready.messages().is_empty() {
    let raft_msgs = self.build_raft_messages(ctx, ready.take_messages());
    self.send_raft_messages(ctx, raft_msgs);   // MsgAppend, votes, …
}
if !ready.committed_entries().is_empty() {
    self.handle_raft_committed_entries(ctx, ready.take_committed_entries());
}
// PeerStorage::handle_raft_ready → WriteTask → raftdb
self.mut_store().handle_raft_ready(&mut ready, destroy_regions)?;
```

#### Persist: unstable entries and HardState → raftdb

`PeerStorage` folds Ready’s **`entries`** (the unstable snapshot) and optional HardState into a write task; the async write worker appends to the shared **raft** engine:

```rust
// PeerStorage::handle_raft_ready
if !ready.entries().is_empty() {
    self.append(ready.take_entries(), &mut write_task);  // EntryStorage cache + task
}
if let Some(hs) = ready.hs() {
    self.raft_state_mut().set_hard_state(hs.clone());
}
if prev_raft_state != *self.raft_state() || !ready.snapshot().is_empty() {
    write_task.raft_state = Some(self.raft_state().clone());
}
```

After the write succeeds, TiKV notifies raft-rs (`on_persist_entries` / `advance`) so **`unstable` can drop the persisted prefix** and `persisted` / match indexes advance. Until that persist (and follower majority acks) completes, the entry is not **committed**. User **kvdb** is still unchanged.

#### Replicate then commit

Ready **`messages`** are the network side of the same propose: typically **`MsgAppend`** carrying the new entries (plus heartbeats / votes from other paths). Followers `step` those messages, append into *their* unstable, run the same Ready persist path on their raftdb, and respond. When a majority has the entry durable, `RaftLog.committed` advances; a later Ready exposes it in `committed_entries`.

#### Apply: committed `Entry.data` → kvdb

The Peer schedules an apply task on the same `region_id`. **ApplyDelegate** parses bytes as `RaftCmdRequest` and writes the KV engine batch:

```rust
// Peer — notify ApplyFsm
ctx.apply_router.schedule_task(
    self.region_id,
    ApplyTask::apply(Apply::new(/* … committed_entries … */)),
);
```

```rust
// ApplyDelegate — per committed Entry
let data = entry.get_data();
let cmd = util::parse_raft_cmd_request(data, index, term, &self.tag);
// …
for req in requests {
    match req.get_cmd_type() {
        CmdType::Put => self.handle_put(ctx, req),      // kv_wb.put_cf(…)
        CmdType::Delete => self.handle_delete(ctx, req),
        // …
    }
}
// ApplyContext::commit → kv_wb.write → Engines.kv
```

`handle_put` checks the key is in the Region, prefixes the data key, and puts into the requested CF (`lock` / `write` / `default`). Flushing the write batch is when **user** state becomes durable on this store. The leader’s client RPC completes only after this apply path (proposal callback), not after propose alone.

```text
propose / step
  → Raft updates role, RaftLog, msgs
  → Ready
       ├─ entries + HardState → PeerStorage → raftdb
       ├─ messages → other peers (followers: step → their raftdb)
       └─ committed_entries → ApplyFsm
            → parse RaftCmdRequest
            → Put/Delete on kvdb CFs
  → (leader) RPC callback
```

**Where bytes land.**

| Bytes | Engine / path |
|-------|----------------|
| HardState + log `Entry` | **raftdb** (`Engines.raft`) |
| Outbound `Message` | Network only |
| Applied `Put` / `Delete` | **kvdb** (`Engines.kv`, MVCC CFs) |

Followers never accept the client write (`NotLeader`); they still apply the same committed entries so their kvdb matches the leader’s applied log.

### 2.2 Message structure (and `term`)

Peer-to-peer Raft RPCs and many local events are one protobuf **`Message`**. Ready’s outbound `messages` and `Peer::step` inputs are this type. Log **`Entry`** bodies that ride inside `Message.entries` (or sit in `RaftLog`) are §2.3.

```protobuf
message Message {
  MessageType msg_type = 1;
  uint64 to = 2;
  uint64 from = 3;
  uint64 term = 4;       // sender's current Raft term (see below)
  uint64 log_term = 5;   // term of the log entry at `index` (matching)
  uint64 index = 6;      // log index this message refers to
  repeated Entry entries = 7;
  uint64 commit = 8;     // leader's committed index (Append / Heartbeat)
  bool reject = 10;
  // … snapshot, reject_hint, context, priority, …
}
```

| Field | Role |
|-------|------|
| `msg_type` | What kind of RPC / local event (`MsgAppend`, `MsgRequestVote`, `MsgHeartbeat`, …) |
| `from` / `to` | Peer ids in the Region’s Raft group |
| **`term`** | **The sender’s current election term** when the message is sent (or `0` for some local messages) |
| `log_term` + `index` | Log matching: “the entry at `index` has term `log_term`” (Append / vote / reject hint) |
| `entries` | New log entries (Append / Propose) |
| `commit` | Leader’s commit index so followers can advance |

**`Message.term` vs other “term” fields.** Raft’s logical clock is a monotonically increasing **term** stored in HardState and in `Raft.term`. Do not confuse:

| Name | Meaning |
|------|---------|
| **`Message.term`** | Current term of the **sender’s Raft instance** (who claims leadership / candidacy now) |
| **`Entry.term`** | Term in which **that log entry** was proposed (fixed once appended) — §2.3 |
| **`Message.log_term`** | Term of the log entry at **`Message.index`** (prev-log matching on Append; last-log info on Vote) |
| **`HardState.term`** | This peer’s persisted current term |

When raft-rs **sends** a network message, it normally stamps `m.term = self.term` (except `MsgPropose` / `MsgReadIndex`, which stay local-style with term `0` until forwarded). Receivers use **`Message.term` first** in `Raft::step`:

```rust
// Raft::step — term gate before role-specific handling
if m.term > self.term {
    // higher term wins: step down (become_follower), then process
    if m.get_msg_type() == MsgAppend || MsgHeartbeat || MsgSnapshot {
        self.become_follower(m.term, m.from);  // recognize sender as leader
    } else {
        self.become_follower(m.term, INVALID_ID);
    }
} else if m.term < self.term {
    // stale leader / candidate: ignore or reply with newer term
    // (e.g. reject Append/Heartbeat so they learn the higher term)
}
// then step_leader / step_candidate / step_follower(m)
```

So **`Message.term` enforces a single timeline**: a leader from an old term cannot overwrite a peer that has already moved on; a candidate with a higher term forces everyone else to follow. **`Entry.term` / `log_term`** enforce **log consistency** (same index must carry the same entry term), which is separate from “who is the current leader.”

### 2.3 Raft log (`RaftLog`, `Unstable`, `Entry`)

The replicated log is **`Raft.raft_log: RaftLog`**. It is an ordered sequence of **`Entry`** values. Commit advances a contiguous prefix (`committed`); apply consumes that prefix into the state machine (`applied`).

![Raft log: commitIndex and apply](images/raft-log.svg)

| Piece | Role |
|-------|------|
| **`store`** (`PeerStorage`) | Entries (and HardState) already written to **raftdb** |
| **`unstable`** | Entries (and optional snapshot) not yet persisted; filled by `append_entry` / follower append |
| **`committed`** | Highest index known majority-replicated (`commitIndex`) |
| **`applied`** | Highest index handed to ApplyFsm (`lastApplied` ≤ `committed`) |

```text
index:  1        2        3        4
term:   1        1        2        2
        [==== committed ====]
                 ^
            applied may lag committed until ApplyFsm catches up
```

#### Entry fields

```protobuf
enum EntryType {
  EntryNormal = 0;
  EntryConfChange = 1;
  EntryConfChangeV2 = 2;
}

message Entry {
  EntryType entry_type = 1;
  uint64 term = 2;           // leader currentTerm when created
  uint64 index = 3;          // position in the log
  bytes data = 4;            // type-dependent payload
  bytes context = 6;         // optional proposal context
}
```

| Field | Function |
|-------|----------|
| **`index`** | Contiguous position; leaders assign `last_index + 1` on propose |
| **`term`** | Election term that created this slot; fixed for that entry |
| **`data`** | Payload interpreted by **`entry_type`** (below) |
| **`entry_type`** | Which of the three log kinds this slot is |
| **`context`** | Opaque side channel (TiKV proposal callback id, etc.) |

#### Entry types (all kinds, with examples)

raft-rs defines exactly three `EntryType` values. TiKV uses all of them.

**1. `EntryNormal` — user / admin Raft commands (or empty noop).**  
`data` is usually a serialized **`RaftCmdRequest`**. Apply decodes Puts/Deletes onto MVCC CFs (§3). An **empty** `EntryNormal` (no `data`) is the leader’s first noop after `become_leader`, used to commit prior-term entries.

```text
# Prewrite lock (typical TiKV write)
Entry {
  entry_type: EntryNormal,
  term:  3,
  index: 42,
  data:  RaftCmdRequest {
    header: { region_id, peer, region_epoch, … },
    requests: [
      Put { cf: "lock", key: <user key>, value: <Lock { startTS, primary, … }> }
      // optional: Put { cf: "default", … }
    ]
  }
}

# Commit (clear lock + write record)
Entry {
  entry_type: EntryNormal,
  term:  3,
  index: 43,
  data:  RaftCmdRequest {
    requests: [
      Put    { cf: "write", key: <user key>@commitTS, value: <Write { startTS, … }> },
      Delete { cf: "lock",  key: <user key> }
    ]
  }
}

# Leader noop after election (commit barrier for prior term)
Entry {
  entry_type: EntryNormal,
  term:  4,          // new leader’s term
  index: 44,
  data:  <empty>
}
```

**2. `EntryConfChange` — single membership change (v1).**  
`data` is a **`ConfChange`**: add / remove voter or add learner, one peer at a time. TiKV still accepts this type on apply; new proposals prefer V2.

```text
Entry {
  entry_type: EntryConfChange,
  term:  5,
  index: 50,
  data:  ConfChange {
    change_type: AddNode,      // or RemoveNode / AddLearnerNode
    node_id: 1003,
    context: <optional app bytes>
  }
}
```

**3. `EntryConfChangeV2` — joint consensus / multi-change (v2).**  
`data` is a **`ConfChangeV2`**: one or more `ConfChangeSingle` ops, optional transition mode. An **empty** `ConfChangeV2` (nil data) is used to **leave a joint configuration** automatically when `auto_leave` is set.

```text
# Add a learner and remove a voter in one joint change
Entry {
  entry_type: EntryConfChangeV2,
  term:  6,
  index: 60,
  data:  ConfChangeV2 {
    transition: Auto,          // or Implicit / Explicit
    changes: [
      { change_type: AddLearnerNode, node_id: 1004 },
      { change_type: RemoveNode,     node_id: 1002 }
    ],
    context: <optional>
  }
}

# Empty ConfChangeV2 — leave joint config (auto_leave path)
Entry {
  entry_type: EntryConfChangeV2,
  term:  6,
  index: 61,
  data:  <empty ConfChangeV2>
}
```

| `EntryType` | `data` payload | Typical TiKV use |
|-------------|----------------|------------------|
| **`EntryNormal`** | `RaftCmdRequest` or empty | Prewrite / Commit / admin cmds; leader noop |
| **`EntryConfChange`** | `ConfChange` | Legacy single add/remove peer |
| **`EntryConfChangeV2`** | `ConfChangeV2` (maybe empty) | Region conf change / leave joint |

Apply dispatches on type: `EntryNormal` → CF mutations; conf-change types → update Region membership, then `RawNode::apply_conf_change`.

#### `Unstable` and append

After `MsgPropose`, `append_entry` only mutates memory:

```rust
// Raft::append_entry — leader only
pub fn append_entry(&mut self, es: &mut [Entry]) -> bool {
    let li = self.raft_log.last_index();
    for (i, e) in es.iter_mut().enumerate() {
        e.term = self.term;
        e.index = li + 1 + i as u64;
    }
    self.raft_log.append(es);  // → unstable.truncate_and_append
    true
}

// RaftLog::append
pub fn append(&mut self, ents: &[Entry]) -> u64 {
    self.unstable.truncate_and_append(ents);
    self.last_index()
}
```

`Unstable.offset` is the Raft index of `entries[0]`; `entries[i]` has index `offset + i`. Ready copies `unstable_entries()` into `Ready.entries` for the Peer to flush to raftdb (§2.1); after persist / `advance`, that unstable prefix is dropped so the next propose appends into a fresh buffer.

```text
MsgPropose
  → append_entry → RaftLog.unstable   (memory)
  → bcast_append → Raft.msgs          (memory)
  → Ready.entries / messages
  → raftdb persist + network MsgAppend
  → majority → committed ↑ → ApplyFsm
```

Propose wiring (`RawNode::propose` → `step_leader`) remains in §2.1; this section is the log’s shape, entry kinds, and where bytes sit before Ready.

---

## 3. Writes: MVCC and 2PC

§2 makes an opaque `Entry.data` durable and applied. This section is what those bytes **mean** on TiKV’s write path: how a client mutation is prepared, how **MVCC** is laid out in kvdb, and how **Percolator 2PC** (Prewrite / Commit) uses that layout. The coordinator is the client (TiDB / client-go); each TiKV Region leader only runs local latch + propose + apply.

### 3.1 Write path implementation

A durable user write always ends as one or more CF Puts/Deletes applied through Raft on the Region **leader**. Layers above the peer:

```text
gRPC (Prewrite / Commit / Rollback / …)
  → Storage + TxnScheduler   (latches; conflict / lock checks; build Modify batch)
  → RaftKv                   (engine facade)
  → RaftRouter → Peer        (serialize RaftCmdRequest → propose)   [§2.1]
  → Ready → raftdb + replicate → commit
  → ApplyFsm                 (decode Entry.data → kv_wb Put/Delete)
  → Engines.kv (MVCC CFs)
  → RPC callback
```

| Layer | Role on the write path |
|-------|-------------------------|
| **TxnScheduler** | Per-key latches; run the command (Prewrite/Commit/…) against a snapshot; produce `Modify`s |
| **RaftKv** | Turn the batch into a proposal on the right `region_id`, or serve local reads |
| **Peer / RawNode** | Consensus durability for the serialized `RaftCmdRequest` (§2.1) |
| **ApplyDelegate** | Decode applied entries into CF mutations on **kvdb** |

```rust
// Modify::Put → one RaftCmdRequest Request (CF + key + value)
Modify::Put(cf, k, v) => {
    let mut put = PutRequest::default();
    put.set_key(k.into_encoded());
    put.set_value(v);
    if cf != CF_DEFAULT {
        put.set_cf(cf.to_string());
    }
    req.set_cmd_type(CmdType::Put);
    req.set_put(put);
}
```

```rust
let reqs: Vec<Request> = batch.modifies.into_iter().map(Into::into).collect();
let mut cmd = RaftCmdRequest::default();
cmd.set_header(header);       // region_id, epoch, peer, …
cmd.set_requests(reqs.into());
// → peer.propose(cmd.write_to_bytes())
```

After majority commit, apply is ordinary CF I/O—not a second transaction protocol inside raftstore:

```rust
let cmd = parse_raft_cmd_request(entry.get_data());
process_raft_cmd(apply_ctx, index, term, cmd);
// CmdType::Put → handle_put → kv_wb.put_cf(cf, key, value)
```

Reads (Get / Coprocessor) use the same MVCC in **kvdb**; they do not propose unless the read protocol requires it (e.g. read index). Coprocessor does not bypass Raft for writes.

### 3.2 MVCC column families

User state is multi-versioned in **kvdb**. Intents and commits share that engine:

| CF | Contents |
|----|----------|
| `lock` | Prewrite / pessimistic **intent** (who holds the key, `startTS`, primary, …) |
| `write` | **Commit** records at `commitTS` (and short values inline) |
| `default` | Large values keyed by `startTS` when not inlined in `write` |

![MVCC Lock / Write / Default](images/tikv-distributed-mvcc-txn.svg)

**Read rule (sketch).** A snapshot read at `ts` looks for the latest `write` record with `commitTS ≤ ts` (and no conflicting lock that must be resolved). **Write rule.** A Prewrite installs a `lock` (and maybe `default`); a Commit installs `write` and deletes `lock`.

One RocksDB apply batch is atomic **on one store for one Region**. Keys in other Regions are other Raft groups; cross-Region atomicity is the client’s 2PC over these CFs (§3.4)—not a multi-Region transaction inside one apply.

### 3.3 Write payload: `RaftCmdRequest` on MVCC CFs

Transactional RPCs become ordinary CF mutations **before** propose. Raft has no `Prewrite` message type—only `Entry.data = RaftCmdRequest` with `Put` / `Delete` on CFs.

Logical shape after a Prewrite that takes a lock:

```text
Entry {
  term, index,
  data: RaftCmdRequest {
    header: { region_id, peer, region_epoch, … },
    requests: [
      Put { cf: "lock", key: <user key>, value: <Lock { startTS, primary, … }> },
      // optional: Put { cf: "default", key: <user key>@startTS, value: <blob> }
    ]
  }
}
```

A later **Commit** is another entry—typically `Put` on `write` at `commitTS` plus `Delete` on `lock`:

```text
requests: [
  Put    { cf: "write", key: <user key>@commitTS, value: <Write { startTS, … }> },
  Delete { cf: "lock",  key: <user key> }
]
```

```rust
let mut cmd = Request::default();
cmd.set_cmd_type(CmdType::Put);
cmd.mut_put().set_cf("lock".into());
cmd.mut_put().set_key(key);
cmd.mut_put().set_value(lock_bytes);
let mut req = RaftCmdRequest::default();
req.mut_requests().push(cmd);
entry.set_data(req.write_to_bytes()?.into());
```

| Pointer (peer) | Meaning |
|----------------|---------|
| `commitIndex` | Highest Raft index majority-replicated (raftdb / HardState) |
| `lastApplied` | Highest index applied into MVCC / kvdb (`≤ commitIndex`) |

Log layout and all `EntryType` examples are in §2.3.

### 3.4 2PC: Prewrite and Commit

TiKV implements **Percolator-style 2PC** as two (or more) Region writes. The **client** chooses a primary key, obtains `startTS` / `commitTS` from PD TSO, and issues RPCs to each involved Region **leader**. TiKV does not run a cross-Region coordinator inside `MultiRaftServer`.

| Phase | Client | Typical apply on each Region leader |
|-------|--------|-------------------------------------|
| **Prewrite** | Lock all keys in the txn (primary first) | Write `lock` CF (+ `default` for large values) at `startTS` |
| **Commit** | Commit primary, then secondaries | Write `write` CF at `commitTS`; delete `lock` |
| **Rollback / ResolveLock** | Abort or recover | Clear or finish leftover locks |

```text
Prewrite key:  Lock[key] = { startTS, primary, … }
Commit key:    Write[key]@commitTS; delete Lock[key]
```

![Prewrite / Commit MVCC](images/tikv-2pc-mvcc.svg)

**Single-Region txn.** Prewrite then Commit are two Raft-committed applies on that Region’s leader—two entries, two MVCC updates, same propose/apply path as §3.1.

**Multi-Region txn.** Each Region’s leader runs Prewrite/Commit independently on its key range. Whole-txn atomicity is: **committed iff the primary key’s `write` record exists**. Secondaries and readers that see a lock **resolve** by reading the primary’s MVCC state on its Region (commit, rollback, or wait). That primary-key rule—not a distributed prepare across stores inside TiKV—is the 2PC commit bit.

```text
client (TiDB / client-go)
  ├─ Prewrite(primary) → Region P leader → Raft → lock CF
  ├─ Prewrite(secondaries) → Region S_i leaders → Raft → lock CF
  ├─ Commit(primary) → Region P → Raft → write CF; clear lock
  └─ Commit(secondaries) → Region S_i → Raft → write CF; clear lock
       (async / retry ok: primary Write is the source of truth)
```

Failure modes stay local to the protocol: Prewrite conflict → lock or latch error to the client; majority loss on a Region → that Region cannot commit its phase (`NotLeader` / timeout); undetermined primary → lock resolution polls the primary Region until `write` or rollback appears.
