---
title: "CAP Theory and Raft implementation in TiDB placement driver"
date: 2026-08-08T15:00:00+02:00
categories:
- data
- db
- tidb
tags:
- data
- db
- tidb
keywords:
- raft
- cap
- pd
- etcd
#thumbnailImage: //example.com/image.jpg
---
The **CAP theorem** states what a replicated store can guarantee when the network splits. **Raft** implements CAP’s **CP** choice via majority quorum. This post introduces that theory (C, A, P, partition trade-off, Raft as CP), then details **PD’s** embedded-etcd Raft. TiKV Region Multi-Raft is in [TiKV](../tikv/); PD TSO / locate / schedule surfaces are in [TiDB architecture](../architecture/).
<!--more-->


---

## 1. Theory

Brewer conjectured CAP in 2000; Gilbert and Lynch gave a formal proof in 2002. On a network that can **partition**—messages between some replicas delayed or lost for an unbounded time—a shared-data system cannot simultaneously guarantee:

- **linearizable** reads and writes for the replicated object, and  
- a **non-error response** from **every** non-failed node that receives a request.

That is the theorem. The design question under partition is which guarantee to keep: **C** or **A**. **P** is not optional on real multi-node deployments; partitions occur.

### 1.1 Scope of the theorem

| CAP applies to | CAP does not decide alone |
|----------------|---------------------------|
| Multi-replica read/write of **one logical object** | Single-node stores (no replica set to partition) |
| Behavior **while** replicas cannot communicate | Latency / throughput when the network is healthy (that is closer to PACELC’s “else”) |
| Whether a client operation **succeeds or errors** | SQL isolation levels, foreign keys, or application invariants by themselves |
| Replicated state machines / quorum logs | Whether the product is “highly available” in the ops sense (nines) |

### 1.2 The three properties

| Property | Formal meaning in CAP |
|----------|------------------------|
| **Consistency (C)** | A successful read reflects the latest successful write (**linearizability** for that object): there is a single history all clients agree on. |
| **Availability (A)** | Every request to a **non-failing** node eventually receives a **non-error** response. The node must not wait forever for unreachable peers. |
| **Partition tolerance (P)** | The system continues to function under arbitrary message loss or delay between subsets of nodes. |

Precise distinctions that are often blurred:

- CAP **C** is **not** ACID “consistency” (constraints across rows or tables). It is the **single-copy illusion** for one replicated object.  
- CAP **A** is **not** “three nines uptime.” A node that is up but returns `NotLeader` / timeout while waiting for quorum is **unavailable** in CAP’s sense for that request.  
- **P** is assumed once you deploy across failure domains; the interesting choice is **CP vs AP** when the cut happens.

### 1.3 The partition model

Split the replica set so **no message crosses** the cut for an unbounded time. Clients may still reach nodes inside each component.

![CAP under partition: CP vs AP](images/cap-partition-choice.svg)

| Choice | Rule during the cut | Client on the minority side | Histories |
|--------|---------------------|-----------------------------|-----------|
| **CP** | Commit only with a rule that preserves linearizability (typically a **majority quorum** of the original voter set). | Error, timeout, or “not leader” | One history; minority does not invent a second |
| **AP** | Accept locally without waiting for the other side. | Success | Histories may **fork**; repair later (LWW, vector clocks, CRDTs, …) |

There is no design that keeps linearizability for **all** clients **and** non-error answers on **every** live node for the whole duration of the partition. That impossibility is the theorem—not a product slogan.

**Worked quorum (RF=3).** Voters {A, B, C}; majority = 2. Cut isolates C from {A, B}.

| Side | Can elect / commit under CP (Raft-style majority)? | Under AP? |
|------|-----------------------------------------------------|-----------|
| {A, B} | Yes (2 ≥ majority) | Yes (and may diverge from C) |
| {C} | No (1 < majority) → stall or error | Yes locally → fork possible |

### 1.4 Raft as a CP mechanism

CAP states the trade-off; it does not name an algorithm. **Raft** is one concrete CP answer for a single replicated log: commit only when a **majority** of voters have stored the entry, and allow at most one **Leader** per term so histories do not fork.

| CAP question | Raft answer |
|--------------|-------------|
| How to keep one history? | Commit only prefixes a majority has stored (`commitIndex`) |
| What happens on the minority side? | Cannot elect or commit → client error / stall |
| Split-brain? | One vote per term per peer + majority ⇒ at most one leader per term |

A Raft group of `N` voters has quorum size `majority(N) = ⌊N/2⌋ + 1`. For `N = 3`, majority is 2. **Election and log commit use the same quorum**—that shared rule is why Raft yields CAP’s **CP** outcome for the group.

![Raft protocol: roles, AppendEntries, majority](images/raft-protocol.svg)

| Step | Who | What |
|------|-----|------|
| Client write | Leader only | Append a new log entry locally |
| Replicate | Leader → followers | `AppendEntries` (also used as heartbeat) |
| Commit | Leader | Advance `commitIndex` when a **majority** of voters have matched that index |
| Redirect | Follower / old leader | Tell the client who the leader is (or that there is none during election) |

**Election and liveness detection.** The leader periodically sends `AppendEntries` (with new entries, or empty as a **heartbeat**). Each follower keeps a randomized **election timeout**. Receiving a valid `AppendEntries` from the current leader proves the leader is alive, so the follower **resets** that timer. Followers do not probe the leader; **silence** is the signal. If no valid `AppendEntries` arrives before the timeout—crash, long pause, or a partition that blocks heartbeats—the follower becomes a **Candidate**: increments `currentTerm`, votes for itself, sends `RequestVote`. A peer grants at most one vote per term, and only if the candidate’s log is at least as up-to-date. Majority votes ⇒ **Leader**.

![Raft leader election](images/raft-leader-election.svg)

| Rule | Effect under partition |
|------|------------------------|
| Majority of votes required | Minority component cannot elect |
| One vote per term per peer | At most one leader per term cluster-wide |
| Log up-to-date check | Prefers peers with longer committed history |
| Randomized timeouts | Breaks split votes (two candidates, no majority) |

**Log.** Each entry is `(term, index, command)`. Safety is committing only prefixes a majority has stored.

![Raft log: commitIndex and apply](images/raft-log.svg)

| Pointer | Meaning |
|---------|---------|
| `commitIndex` | Highest index stored on a majority |
| `lastApplied` | Applied to the local state machine (`≤ commitIndex`) |
| Match index | Per-follower agreement with the leader |

Pipeline: **propose** → **persist + replicate** → **commit** (majority) → **apply** (state machine). The majority wait on commit is CAP’s **C** cost on the write path; the minority’s inability to elect is CAP’s sacrificed **A**.

Raft is not CAP itself; it is a **CP implementation** of consensus for one replicated log. In a TiDB cluster that pattern appears twice with different libraries and objects: **PD** (§2, etcd Raft for control-plane meta) and **TiKV** Regions ([TiKV post](../tikv/), `raft-rs` for row data).

---

## 2. PD Raft implementation

Each PD member embeds **etcd**; the PD servers form **one** Raft group whose log holds control-plane state (membership, Region meta keys, leases). The library is Go **`go.etcd.io/etcd/raft`**, inside embedded etcd. PD does **not** call `RequestVote` / `AppendEntries` itself—those RPCs live in etcd. PD **starts** etcd, **observes** term / commit / apply, and layers a **PD leader** lease (`/pd/{cluster}/leader`) on top of that quorum.

| | **PD Raft** (this section) | **TiKV Raft** ([TiKV](../tikv/)) |
|--|----------------------------|----------------------------------|
| **Protects** | PD **membership** and etcd-stored **meta** | Region **data** (KV commands in the Region log) |
| **Library** | Go etcd Raft | Rust `raft-rs` |
| **Groups** | **One** group for the PD members | One group **per Region** (Multi-Raft) |
| **Peers** | PD servers (odd set, typically 3 or 5) | TiKV stores |
| **Client surface** | **PD leader** (TSO / locate / schedule) | Region **leader** (`NotLeader`) |

Same CAP rule from §1.4: majority commit, minority cannot elect a second leader. Different object and different library.

### 2.1 Two leaders: etcd Raft leader vs PD leader

**etcd runs its own Raft.** PD embeds etcd (`go.etcd.io/etcd`); etcd’s consensus library (`go.etcd.io/etcd/raft`) forms **one** Raft group among the PD members. That group must elect a Raft leader—the peer that appends entries, sends `MsgApp` / `MsgVote`, and advances `commitIndex`. PD did not invent a second Raft for meta; it **inherits** etcd’s. “etcd Raft leader” means leader of **etcd’s** Raft group.

The **PD leader** is a separate **application** role. TiDB and TiKV need one PD process to serve TSO, Region locate, and schedule. PD records that primary with a lease and `Put /pd/{cluster}/leader`—a key **inside** etcd’s Raft-replicated KV, not another Raft implementation.

| | **etcd Raft leader** | **PD leader** |
|--|----------------------|---------------|
| **Why it exists** | etcd’s Raft needs a leader to commit the meta log | PD’s API needs one serving primary |
| **Chosen by** | Raft inside etcd (`MsgVote` / PreVote → `etcd.Server.Lead()`) | App campaign: lease + `Put /pd/{cluster}/leader` (via that Raft log) |
| **Owns** | Consensus for meta keys in etcd | Control-plane API and in-memory cluster (`createRaftCluster`) |
| **TiDB / TiKV see** | Indirectly (meta must commit) | Directly (gRPC to the PD leader) |

Calling only “the leader” is ambiguous: Raft leadership ≠ “who answers `Tso` / `GetRegion`.” etcd `Lead()` answers the first; the PD leader key answers the second.

**Why they usually sit on one machine.** `leaderLoop` campaigns for the PD leader key only when `GetEtcdLeader() == self`, so the member that serves PD can commit etcd writes locally. If etcd leadership moves away, the PD leader resigns. You typically observe **one host holding both titles**; the mechanisms remain distinct (etcd’s Raft role vs PD’s lease/key).

```text
PD-A (usual steady state)          PD-B / PD-C
+---------------------------+      +------------------+
| etcd Raft leader          |      | etcd follower    |
| PD leader (lease + key)   |      | watch /pd/.../leader
| serves TSO / locate       |      | no PD API primary|
+---------------------------+      +------------------+
         ^ writes meta via local etcd Lead()
```

### 2.2 Start embedded etcd

`Server.Run` → `startEtcd` boots one etcd peer per PD process (`GenEmbedEtcdConfig` sets tick / election intervals and PreVote). Raft peers then exchange votes and appends **inside** etcd—this elects the **etcd Raft leader**, not yet the PD leader.

```go
// git/pd: server/server.go
func (s *Server) startEtcd(ctx context.Context) (retErr error) {
	etcd, err := embed.StartEtcd(s.etcdCfg)
	if err != nil {
		return errs.ErrStartEtcd.Wrap(err).GenWithStackByCause()
	}
	select {
	case <-etcd.Server.ReadyNotify():
	case <-newCtx.Done():
		return errs.ErrCancelStartEtcd.FastGenByArgs()
	}
	// startClient + initMember ...
	return nil
}
```

```go
// git/pd: server/config/config.go — GenEmbedEtcdConfig (excerpt)
cfg := embed.NewConfig()
cfg.PreVote = c.PreVote
cfg.TickMs = uint(c.TickInterval.Duration / time.Millisecond)
cfg.ElectionMs = uint(c.ElectionInterval.Duration / time.Millisecond)
```

### 2.3 Election (align etcd leader, then campaign PD leader)

After §2.1: first become **etcd Raft leader**, then **Campaign** for the **PD leader** key. `leaderLoop` skips campaigning unless this member is etcd leader; otherwise it watches an existing PD leader or waits.

```go
// git/pd: server/server.go — leaderLoop (simplified)
func (s *Server) leaderLoop() {
	for {
		leader, checkAgain := s.member.CheckLeader()
		if leader != nil {
			leader.Watch(s.serverLoopCtx) // block until PD leader changes
			continue
		}
		etcdLeader := s.member.GetEtcdLeader() // etcd.Server.Lead() — Raft role
		if etcdLeader != s.member.ID() {
			time.Sleep(200 * time.Millisecond)
			continue // do not Campaign PD leader on a non-etcd-leader
		}
		s.campaignLeader() // now seek PD leader lease + key
	}
}
```

```go
// git/pd: pkg/member/member.go
func (m *Member) GetEtcdLeader() uint64 {
	return m.etcd.Server.Lead()
}
```

```go
// git/pd: pkg/election/leadership.go — Campaign (excerpt)
func (ls *Leadership) Campaign(leaseTimeout int64, leaderData string, cmps ...clientv3.Cmp) error {
	if err := newLease.Grant(leaseTimeout); err != nil {
		return err
	}
	finalCmps = append(finalCmps, clientv3.Compare(clientv3.CreateRevision(ls.leaderKey), "=", 0))
	resp, err := kv.NewSlowLogTxn(ls.client).
		If(finalCmps...).
		Then(clientv3.OpPut(ls.leaderKey, leaderData, clientv3.WithLease(newLease.GetID()))).
		Commit()
	// Succeeded ⇒ Put entered the etcd Raft log and committed
	return nil
}
```

That `OpPut` is how PD leadership is **recorded**: the etcd Raft leader appends it, replicates with `MsgApp` (AppendEntries), and commits only with a majority—same CP rule as §1.4. Winning the key does not replace Raft; it depends on it.

### 2.4 Heartbeat and leadership keep-alive

**Raft heartbeats** (`MsgApp` with no new entries) are sent by the **etcd Raft leader** on its tick; PD never issues them.

**PD leadership** stays alive via an etcd **lease** renew loop after a successful campaign. If the lease expires, or **etcd** leadership moves away, the member steps down as **PD** leader—again keeping the two roles aligned.

```go
// git/pd: server/server.go — campaignLeader (excerpt)
func (s *Server) campaignLeader() {
	if err := s.member.Campaign(s.ctx, s.cfg.LeaderLease); err != nil {
		return
	}
	s.member.GetLeadership().Keep(ctx) // renew lease until resign
	// createRaftCluster / enable TSO ... then serve while IsServing()
}
```

```go
// git/pd: pkg/election/leadership.go
func (ls *Leadership) Keep(ctx context.Context) {
	ls.keepAliveCtx, ls.keepAliveCancelFunc = context.WithCancel(ctx)
	go ls.GetLease().KeepAlive(ls.keepAliveCtx) // KeepAliveOnce on an interval
}
```

Serving check (lease still valid and self is PD leader):

```go
// git/pd: pkg/member/member.go
func (m *Member) IsServing() bool {
	return m.leadership.Check() && m.GetLeader().GetMemberId() == m.member.GetMemberId()
}
```

### 2.5 Raft log (commit and apply)

etcd owns the replicated log. A successful PD `Campaign` (or any other meta write) becomes one or more log entries; after majority match, `CommittedIndex` advances and the etcd state machine applies into its MVCC store (`AppliedIndex`). **Sending the log and transferring state happen inside etcd’s Raft**—PD only embeds the process and reads the indexes.

The figure below is a **concrete cluster-714 slice**: after `pd1` becomes etcd leader it `Put`s `/pd/714/leader` (Campaign), persists `/pd/714/timestamp` (TSO window), and begins replicating Region 27 meta at `/pd/714/raft/r/…027`—real key shapes from `git/pd` `pkg/utils/keypath`.

![PD etcd Raft log example](images/pd-etcd-raft-log.svg)

#### Send log entries (`MsgApp`) or snapshot (`MsgSnap`)

After a propose (e.g. PD’s `OpPut /pd/714/leader`), the etcd Raft **leader** replicates to each follower. `bcastAppend` walks progress; `maybeSendAppend` either ships log entries or, if the follower is too far behind to get entries from the leader’s log, ships a **snapshot** (full state transfer).

```go
// go.etcd.io/etcd/raft: raft.go — leader replicates to all other peers
func (r *raft) bcastAppend() {
	r.prs.Visit(func(id uint64, _ *tracker.Progress) {
		if id == r.id {
			return
		}
		r.sendAppend(id)
	})
}

func (r *raft) maybeSendAppend(to uint64, sendIfEmpty bool) bool {
	pr := r.prs.Progress[to]
	term, errt := r.raftLog.term(pr.Next - 1)
	ents, erre := r.raftLog.entries(pr.Next, r.maxMsgSize)
	if errt != nil || erre != nil {
		// Follower is behind compacted log → state transfer via snapshot
		m.Type = pb.MsgSnap
		m.Snapshot = snapshot // from r.raftLog.snapshot()
		pr.BecomeSnapshot(sindex)
	} else {
		m.Type = pb.MsgApp // AppendEntries
		m.Index, m.LogTerm = pr.Next-1, term
		m.Entries, m.Commit = ents, r.raftLog.committed
	}
	r.send(m)
	return true
}
```

Empty `MsgApp` / `MsgHeartbeat` also carry an updated `Commit` so followers can advance `commitIndex` without new data.

#### Follower append and snapshot restore

```go
// go.etcd.io/etcd/raft: raft.go — follower handles AppendEntries
func (r *raft) handleAppendEntries(m pb.Message) {
	if mlastIndex, ok := r.raftLog.maybeAppend(m.Index, m.LogTerm, m.Commit, m.Entries...); ok {
		r.send(pb.Message{To: m.From, Type: pb.MsgAppResp, Index: mlastIndex})
	} else {
		r.send(pb.Message{To: m.From, Type: pb.MsgAppResp, Index: m.Index, Reject: true, /* RejectHint */})
	}
}

// State transfer when MsgApp cannot catch up
func (r *raft) handleSnapshot(m pb.Message) {
	if r.restore(m.Snapshot) {
		r.send(pb.Message{To: m.From, Type: pb.MsgAppResp, Index: r.raftLog.lastIndex()})
	} else {
		r.send(pb.Message{To: m.From, Type: pb.MsgAppResp, Index: r.raftLog.committed})
	}
}
```

On `MsgAppResp` without reject, the leader updates match progress and may commit:

```go
// go.etcd.io/etcd/raft: raft.go
func (r *raft) maybeCommit() bool {
	mci := r.prs.Committed() // highest index replicated to a majority
	return r.raftLog.maybeCommit(mci, r.Term)
}
// After commit advances: bcastAppend() again so followers learn the new Commit
```

#### Ready loop: network send + apply (state machine)

etcdserver’s raft node drains `Ready()`: persist hard state / entries, push **committed** entries (and optional snapshot) to the apply channel, and on the leader **send** outbound Raft messages on the wire.

```go
// go.etcd.io/etcd/server/etcdserver: raft.go — raftNode.start (excerpt)
case rd := <-r.Ready():
	ap := apply{
		entries:  rd.CommittedEntries, // majority-committed → apply to etcd MVCC
		snapshot: rd.Snapshot,           // install if state was transferred
		notifyc:  notifyc,
	}
	updateCommittedIndex(&ap, rh)
	r.applyc <- ap
	if islead {
		r.transport.Send(r.processMessages(rd.Messages)) // MsgApp / MsgSnap / heartbeats
	}
```

Pipeline for the cluster-714 example: **propose** `Put /pd/714/leader` → leader **`MsgApp`** (or **`MsgSnap`**) → followers **`MsgAppResp`** → **`maybeCommit`** → **`CommittedEntries` applied** → PD’s `AppliedIndex` / `CommittedIndex` gauges move.

| Pointer (etcd API) | Meaning for PD |
|--------------------|----------------|
| `Term()` | Current Raft term of the embedded peer |
| `CommittedIndex()` | Highest index replicated to a majority |
| `AppliedIndex()` | Highest index applied to etcd’s local KV (`≤` committed) |
| `Lead()` | Current etcd Raft leader member ID |

PD surfaces those fields as Prometheus gauges (`pd_server_etcd_state`):

```go
// git/pd: server/server.go
func (s *Server) collectEtcdStateMetrics() {
	etcdTermGauge.Set(float64(s.member.Etcd().Server.Term()))
	etcdAppliedIndexGauge.Set(float64(s.member.Etcd().Server.AppliedIndex()))
	etcdCommittedIndexGauge.Set(float64(s.member.Etcd().Server.CommittedIndex()))
}
```

Under partition, the minority PD side cannot advance this log or keep the PD lease. TiDB clients that need TSO or Region meta against a non-leader PD see not-leader and retry—CAP’s CP outcome for the **control plane**, independent of any TiKV Region’s Raft group.

PD Raft does **not** replicate row values. Losing PD majority stalls TSO and meta updates; existing TiKV Region majorities can still commit until the client needs a fresh TSO or cache fill from PD.

### 2.6 Key files (`git/pd`)

| Location | Role |
|----------|------|
| `server/server.go` | `startEtcd`, `leaderLoop`, `campaignLeader`, `collectEtcdStateMetrics` |
| `server/config/config.go` | `GenEmbedEtcdConfig`, `LeaderLease`, election tick |
| `pkg/member/member.go` | `Campaign`, `GetEtcdLeader`, `IsServing`, `MoveEtcdLeader` |
| `pkg/election/leadership.go` | lease `Campaign` / `Keep` / `Watch` |
| `pkg/election/lease.go` | `Grant`, `KeepAlive` / `KeepAliveOnce` |
| Embedded etcd (`go.etcd.io/etcd/raft`) | `bcastAppend` / `maybeSendAppend` (`MsgApp`/`MsgSnap`), `handleAppendEntries`, `handleSnapshot`, `maybeCommit` |
| Embedded etcd (`go.etcd.io/etcd/server/etcdserver`) | `raftNode` Ready loop: `transport.Send`, apply `CommittedEntries` |

---

## Scope

Covered: CAP theory (properties, partition model, CP vs AP, Raft as CP); PD embedded-etcd Raft and why etcd Raft leader ≠ PD leader; start, election, keep-alive, log send/commit/apply with source snippets. TiKV Region Multi-Raft (`raft-rs`), `NotLeader`, and `CommitLog`: [TiKV](../tikv/). Region key ranges, TSO allocation, and schedule operators: [architecture §3](../architecture/). Not covered: PACELC, Dynamo/AP designs, Byzantine faults, or a full etcd FSM walkthrough.
