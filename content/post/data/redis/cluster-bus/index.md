---
title: "Redis Internals: Cluster Bus Gossip Protocol"
date: 2026-07-21T23:30:00+02:00
categories:
- data
- cache
tags:
- data
- cache
- redis
keywords:
- redis
- cluster
- gossip
- cluster-bus
#thumbnailImage: //example.com/image.jpg
---

Redis Cluster keeps a second network plane beside client RESP: the **cluster bus**. Nodes use it to discover peers, share slot and epoch views, detect failures, vote on failovers, and propagate selected cluster events. This post covers **architecture** (planes and gossip mechanism), then **implementation** (protocol wire format and code paths) in `git/redis` (`cluster_legacy.h`, `cluster_legacy.c`).

<!--more-->

Related: [Network / command path](../architecture/), [Pub/Sub](../pubsub/), [Build from source](../build/).

![Cluster bus gossip overview](images/cluster-bus-gossip.svg)

---

## 1. Architecture

Redis Cluster’s control architecture is a **node-to-node mesh** on a dedicated **cluster bus** port, separate from client RESP. Each node holds a local membership and slot view and exchanges binary `clusterMsg` packets—periodic gossip for liveness and topology, plus discrete messages for failure, failover, and selected events.

### 1.1 Two planes

Redis Cluster separates **data** traffic from **control** traffic. Clients stay on RESP; only Redis nodes speak the binary bus protocol.

| Plane | Port (typical) | Speakers | Role |
|-------|----------------|----------|------|
| Client / data | `:6379` RESP | Apps, replication client | Commands, keys, replication stream |
| Cluster bus / control | `:16379` (base+10000) binary | Redis nodes only | Membership, health, slots/epochs, votes, selected events |

```text
 clients --RESP--> [ Redis node: data + slots ]
                        |
                        | bus TCP (clusterMsg)
                        v
                   peer ... peer
```

The bus does not carry ordinary key commands. Gossip scales membership and health without shipping a full node list on every packet.

### 1.2 Gossip mechanism

Gossip is how Redis Cluster spreads **membership and health** without shipping a full node list on every packet. It rides only on `PING` / `PONG` / `MEET`: the fixed **header** always describes the sender (epochs, `myslots`, flags, …); the **body** carries a **sample** of rumors about other nodes (`clusterMsgDataGossip` rows). Discrete types (`FAIL`, `UPDATE`, Pub/Sub, failover votes, …) are separate events on the same links—they are not the gossip sampler.

| Pattern | Types | Cadence | Purpose |
|---------|-------|---------|---------|
| Continuous gossip | `PING`, `PONG`, `MEET` | Periodic / on meet | Liveness, membership rumors, slot/epoch in **header**, failure flags in gossip rows |
| Discrete events | `FAIL`, `FAILOVER_AUTH_*`, `UPDATE`, `PUBLISH` / `PUBLISHSHARD`, `MFSTART`, `MODULE` | On demand | Explicit flood or unicast for one cluster action |

Wire layouts for those types are in [§2.3](#23-data-by-message-type).

#### 1.2.1 Exchange

`PING`, `PONG`, and `MEET` share the same packet kind (`data.ping`). Semantics differ:

| Type | Role |
|------|------|
| `PING` | Probe; receiver should answer with `PONG` |
| `PONG` | Reply; completes the liveness round-trip and carries the receiver’s own gossip sample |
| `MEET` | Like `PING`, but forces the receiver to **add** the sender if unknown |

```mermaid
sequenceDiagram
  participant A as Node A
  participant B as Node B
  A->>B: MEET or PING
  Note right of B: apply header, merge gossip sample
  B->>A: PONG
  Note left of A: apply header, merge gossip sample
```

**Default frequency.** `clusterCron` runs every **100 ms**. Ping timing is driven by `cluster-node-timeout` (default **15000 ms** / 15 s in `redis.conf` / `config.c`):

| Path | Default behavior |
|------|------------------|
| Per-peer refresh | If there is no outstanding ping and the last `PONG` from that peer is older than **`cluster-node-timeout / 2`** (**7500 ms** with the default timeout), send a `PING`. Override with hidden `cluster-ping-interval` (ms) when non-zero. |
| Random probe | About once per **second** (`iteration % 10` in `clusterCron`), pick among a few random peers and `PING` the one with the oldest `pong_received`. |
| `PONG` | Immediate reply to `PING` or `MEET` (same packet shape); not on a separate timer. |
| `PFAIL` | If a ping is still unanswered for longer than **`cluster-node-timeout`** (15 s default), the peer is marked locally unreachable. |

So under defaults, a healthy peer is typically re-pinged on the order of **every ~7.5 s** when its last pong ages out, plus occasional random pings (~1/s cluster-wide toward the stalest sample). Manual-failover wait may ping the chosen replica continuously.

Each successful exchange updates the sender from the peer’s header and merges the peer’s gossip rows into the local `nodes` dictionary.

#### 1.2.2 Sampling

The body never lists the whole cluster. `clusterSendPing` builds a **bounded random sample**, then forces failure opinions into that sample:

| Step | Rule |
|------|------|
| Budget | `wanted = max(3, floor(N / 10))`, where `N = dictSize(nodes)` |
| Cap | At most `freshnodes = N - 2` (exclude self and the packet’s receiver) |
| Draw | Pick eligible peers at random (skip handshake / no-addr cases the send loop rejects); use `last_in_ping_gossip` so the same node is not repeated in one ping wave |
| PFAIL bias | After the random draw, **append every node the sender already marks `PFAIL`**, even if that exceeds `wanted` |
| Wire | Set `hdr->count` to the number of gossip entries actually written |

**Why ~1/10 (and at least three).** Source comment on `clusterSendPing`: within about two `cluster-node-timeout` windows, nodes exchange several pings/pongs. With ~`N/10` gossip slots per packet, the chance that a given master appears often enough in others’ samples is high enough that a node already in `PFAIL` can collect **majority** failure reports before reports expire—without paying full-membership bandwidth every round.

**What each sampled row carries.** A rumor about one third party: id, coarse `ping_sent` / `pong_received` (seconds), IP and ports, and that peer’s `flags` as the **sender** sees them (`MASTER` / `SLAVE` / `PFAIL` / `FAIL` / `NOADDR`, …). Exact field sizes are under [§2.3.1](#231-ping--pong--meet-02--dataping).

#### 1.2.3 Merge

`clusterProcessGossipSection` validates node ids, then for each row:

1. **Corrupt ids** — reject the entire gossip section.
2. **Known node, not myself** — if the packet sender is a master and the row has `PFAIL`/`FAIL`, record a failure report (and maybe promote to `FAIL`); if the row clears failure flags, drop that master’s report. Optionally refresh local `pong_received`. If the subject is down locally but gossip says it is up at a new address, update IP/ports and drop the old link.
3. **Unknown node** — if the sender is a trusted cluster member, the row is not `NOADDR`, and the id is not blacklisted, insert a new `clusterNode`.
4. **Gossip about myself** — ignored for state updates.

Over many rounds, random samples plus PFAIL bias yield cluster-wide convergence on membership and failure views with \(O(N)\) rumor bytes per packet rather than \(O(N^2)\) full dumps.

#### 1.2.4 Failure detection (weak quorum)

Failure is a **local opinion** that becomes a **cluster flag** only with majority support among masters that serve slots. Gossip sampling is what spreads those opinions:

1. If A cannot reach X within `cluster-node-timeout`, A sets **local** `PFAIL` on X.
2. Masters advertise `PFAIL`/`FAIL` in **gossip rows**; peers record **failure reports** from masters. PFAIL bias in [§1.2.2 Sampling](#122-sampling) accelerates this.
3. If A already has `PFAIL` on X and reports from a **majority of masters** (quorum \((\mathit{cluster\_size}/2)+1\)), A sets `FAIL`, clears `PFAIL`, and broadcasts a discrete `FAIL` message (`data.fail`) so others can adopt the flag without waiting for another gossip round.
4. Reachability again can clear `FAIL` under defined conditions (especially for replicas).

![Failure detection PFAIL to FAIL](images/failure-detection.svg)

This agreement is intentionally weak and time-based: partitions may delay visibility, and without majority no replica promotion is authorized.

#### 1.2.5 Replica promotion (to master)

Once the failed master is `FAIL`, a replica of that master may try to take over on the same bus:

1. Replica `R` broadcasts `FAILOVER_AUTH_REQUEST` (header carries epochs and claimed `myslots`; body empty). For manual failover, `MFSTART` runs first and `FORCEACK` may be set on the request.
2. Slotted masters that accept the vote reply with unicast `FAILOVER_AUTH_ACK`.
3. When `R` collects enough acks (`failover_auth_count` reaches quorum), it promotes: `SLAVE` → `MASTER`, claims the former master’s slots, bumps `configEpoch`.
4. Peers learn the new owner through subsequent gossip headers and optional `UPDATE` packets so client `MOVED` targets point at `R`.

![Replica promotion after master FAIL](images/replica-promote.svg)

Wire layouts: [§2.3.4](#234-failover_auth_request-5--empty-data)–[§2.3.6](#236-update-7--dataupdate), [§2.3.7](#237-mfstart-8--empty-data).

#### 1.2.6 Design properties (gossip)

| Property | Consequence |
|----------|-------------|
| Sampled gossip + PFAIL bias | Bandwidth grows gently with \(N\); failures propagate faster than uniform random gossip |
| Weak majority for `FAIL` | Avoids single-observer false failovers; still partition-sensitive |
| Header + sample each ping | Topology and health refresh continuously without a full membership dump |

---

## 2. Implementation

### 2.1 Links and packet ingress

```c
/* cluster_legacy.h */
typedef struct clusterLink {
    connection *conn;
    list *send_msg_queue;
    char *rcvbuf;
    clusterNode *node;   /* NULL until sender is known */
    int inbound;
    /* ... */
} clusterLink;
```

`clusterCron` (and related paths) open outbound links and schedule pings. Inbound data accumulates in `rcvbuf` until a full `clusterMsg` is present; `clusterProcessPacket` branches on `type`.

### 2.2 Protocol design

#### 2.2.1 Framing

Every bus packet is one binary `clusterMsg`: fixed header, then a `type`-specific `data` body. Signature `RCmb`, protocol version 1; field offsets are ABI-stable across upgrades.

1. **Header always describes the sender** — id, IP, ports, flags, full slot bitmap (`myslots`), `currentEpoch` / `configEpoch`, replication offset, cluster state. Receivers refresh the sender from the header even when they care mainly about the body.
2. **Body is typed** — gossip arrays for the ping family; failed node name for `FAIL`; channel+payload for publish; slot config for `UPDATE`; module blob for `MODULE`; often empty for vote / `MFSTART` (meaning is in `type` + header epochs/flags).
3. **Trust boundary** — unknown senders are ignored for sensitive types. `MEET` is the intentional exception that **creates** knowledge of the sender.

![clusterMsg header and typed data](images/cluster-msg-layout.svg)

#### 2.2.2 Header fields

The fixed header ends at offset 2256 (`data` begins there). Multi-byte integers are sent in network byte order. Offsets below are from `static_assert` in `cluster_legacy.h`.

| Field | Offset | Size | Meaning |
|-------|--------|------|---------|
| `sig` | 0 | 4 | Must be the ASCII bytes `RCmb` (Redis Cluster message bus). Used to reject non-bus data on the TCP stream. |
| `totlen` | 4 | 4 | Total packet length in bytes, including this header and the typed `data` section. Receiver waits until `rcvbuf` holds at least `totlen` before calling `clusterProcessPacket`. |
| `ver` | 8 | 2 | Wire protocol version; currently `CLUSTER_PROTO_VER` = 1. Nodes reject packets with an unsupported version. |
| `port` | 10 | 2 | Sender’s **primary** client port (TCP or TLS, whichever is primary for that node). Used with `myip` / gossip to reach the peer for RESP. |
| `type` | 12 | 2 | `CLUSTERMSG_TYPE_*` (0–10). Selects how `data` is interpreted; see [§2.3](#23-data-by-message-type). |
| `count` | 14 | 2 | For `PING` / `PONG` / `MEET`: number of `clusterMsgDataGossip` entries in `data.ping`. Unused (typically 0) for other types. |
| `currentEpoch` | 16 | 8 | Cluster epoch as known by the sender—the logical clock advanced on failover elections. Peers adopt a higher epoch when they see one. |
| `configEpoch` | 24 | 8 | If the sender is a **master**: its own config epoch for the slots it claims. If a **replica**: the config epoch last advertised by its master. Drives which slot map wins on conflict. |
| `offset` | 32 | 8 | If master: replication offset. If replica: offset processed from the master. Used in failover ranking and manual-failover catch-up (`mf_master_offset` path). |
| `sender` | 40 | 40 | Sender node id (`CLUSTER_NAMELEN`), 40-byte hex SHA1-style name. Primary key in the receiver’s `nodes` dictionary. |
| `myslots` | 80 | 2048 | Bitmap of 16384 slots (`CLUSTER_SLOTS/8` bytes). Bit set ⇒ sender claims that slot (as master). Refreshed on every gossip packet so peers keep `MOVED` targets current. |
| `slaveof` | 2128 | 40 | If the sender is a replica: master’s node id. If master: typically all zeros / null name. |
| `myip` | 2168 | 46 | Sender IP string (`NET_IP_STR_LEN`), if not all zeroed. Peers may update the known address when this is present and trusted. |
| `extensions` | 2214 | 2 | For ping-family packets with extension payloads: number of extension records after the gossip array. |
| `notused1` | 2216 | 30 | Reserved; must remain at this offset for ABI stability across upgrades. |
| `pport` | 2246 | 2 | **Secondary** client port: if `port` is TCP, this is TLS (and the reverse). Zero when unused. |
| `cport` | 2248 | 2 | Sender’s **cluster bus** TCP port (often `port + 10000` unless announced otherwise). |
| `flags` | 2250 | 2 | Sender’s `CLUSTER_NODE_*` flags (bitmask), e.g. `MASTER`, `SLAVE`, `PFAIL`, `FAIL`, `HANDSHAKE`, `NOADDR`, `NOFAILOVER`, … |
| `state` | 2252 | 1 | Cluster state from the sender’s point of view: `CLUSTER_OK` (0) or `CLUSTER_FAIL` (1). |
| `mflags` | 2253 | 3 | Per-message flags. Byte 0 (`CLUSTERMSG_FLAG0_*`): `PAUSED` (master paused for manual failover), `FORCEACK` (grant failover auth even if master is up), `EXT_DATA` (ping body includes extensions). Bytes 1–2 reserved. |

**How receivers use the header.** After validating `sig`, `ver`, and `totlen`, the node looks up or creates the `clusterNode` for `sender`, then copies reachability-related fields (ports, `myip`, `flags`, epochs, `myslots`, `slaveof`, `offset`, `state`) according to the processing rules for that `type`. Gossip rows in `data` describe *other* nodes; the header is always the sender’s self-description.

**Flags worth recognizing on the wire.**

| Bit | Name | Role |
|-----|------|------|
| 1 | `MASTER` | Node is a master |
| 2 | `SLAVE` | Node is a replica |
| 4 | `PFAIL` | Suspected failure (local opinion) |
| 8 | `FAIL` | Failed after majority agreement |
| 16 | `MYSELF` | This process (local use) |
| 32 | `HANDSHAKE` | First exchange not finished |
| 64 | `NOADDR` | Address unknown |
| 128 | `MEET` | Pending `MEET` to this node |
| 512 | `NOFAILOVER` | Replica will not start failover |
| 1024 | `EXTENSIONS_SUPPORTED` | Peer understands ping extensions |

In the **header**, `flags` describe the **sender** (normally `MASTER` or `SLAVE`, plus capability bits). `PFAIL` / `FAIL` matter most in **gossip rows** (see [§1.2](#12-gossip-mechanism)), where they are the sender’s opinion about *other* nodes and feed failure reports.

### 2.3 Data by message type

`hdr->type` selects the `union clusterMsgData` arm. The fixed header ([§2.2.2](#222-header-fields)) is always present; only `data` (and how `count` / `mflags` / epochs are interpreted) changes.

| § | Type | Id | `data` arm |
|---|------|----|------------|
| [2.3.1](#231-ping--pong--meet-02--dataping) | `PING` / `PONG` / `MEET` | 0–2 | `data.ping` |
| [2.3.2](#232-fail-3--datafail) | `FAIL` | 3 | `data.fail` |
| [2.3.3](#233-publish-4--publishshard-10--datapublish) | `PUBLISH` / `PUBLISHSHARD` | 4 / 10 | `data.publish` |
| [2.3.4](#234-failover_auth_request-5--empty-data) | `FAILOVER_AUTH_REQUEST` | 5 | (empty) |
| [2.3.5](#235-failover_auth_ack-6--empty-data) | `FAILOVER_AUTH_ACK` | 6 | (empty) |
| [2.3.6](#236-update-7--dataupdate) | `UPDATE` | 7 | `data.update` |
| [2.3.7](#237-mfstart-8--empty-data) | `MFSTART` | 8 | (empty) |
| [2.3.8](#238-module-9--datamodule) | `MODULE` | 9 | `data.module` |

#### 2.3.1 `PING` / `PONG` / `MEET` (0–2) — `data.ping`

**Role.** Continuous gossip: liveness round-trip plus membership rumors. `MEET` additionally inserts the sender if unknown.

**Body layout.**

```text
data.ping
+------------------+-----+------------------+------------------------+
| gossip[0]        | ... | gossip[count-1]  | ping extensions (opt.) |
+------------------+-----+------------------+------------------------+
  sizeof(clusterMsgDataGossip) each           hdr->extensions records
```

- `hdr->count` = number of gossip entries (see [§1.2.2 Sampling](#122-sampling)).
- Optional extensions follow `&gossip[count]` when `mflags[0]` has `CLUSTERMSG_FLAG0_EXT_DATA` (`getInitialPingExt`).

**Gossip entry** (`clusterMsgDataGossip`) — rumor about a **third** node, filled by `clusterSetGossipEntry`:

| Field | Size | Content |
|-------|------|---------|
| `nodename` | 40 | Subject node id |
| `ping_sent` | 4 | Last ping to that node, **seconds** (`n->ping_sent/1000`) |
| `pong_received` | 4 | Last pong from that node, **seconds** |
| `ip` | 46 | Last known IP |
| `port` | 2 | Primary client port (TCP/TLS per cluster mode) |
| `cport` | 2 | Cluster bus port |
| `flags` | 2 | Sender’s view of that node’s `CLUSTER_NODE_*` flags |
| `pport` | 2 | Secondary client port |
| `notused1` | 2 | Reserved; 0 |

**Extensions** (after the array, 8-byte aligned):

| Ext type | Payload | Purpose |
|----------|---------|---------|
| `HOSTNAME` | NUL-terminated hostname | Announced hostname |
| `HUMAN_NODENAME` | NUL-terminated name | Human-friendly node name |
| `FORGOTTEN_NODE` | node id + TTL (s) | Temporary blacklist |
| `SHARDID` | 40-byte shard id | Shard identity |
| `INTERNALSECRET` | 40-byte secret | Shard internal secret |

**Example (PING / PONG).** `A` sends `PING` to `B` with `count = 4` (three random peers + one `PFAIL`). `B` merges gossip, replies `PONG` with its own header and sample.

**Example (MEET).** Operator runs `CLUSTER MEET 10.0.0.5 7000` on node `A`. `A` opens a bus TCP connection to `10.0.0.5:17000` (client port + 10000) and sends a packet with `type = MEET`, the same `data.ping` layout as a ping (header describes `A`, body is a gossip sample). New node `N` does not yet know `A`: because the type is `MEET`, it inserts `A` into `nodes`, then replies with `PONG` (same body shape). Later membership grows through ordinary `PING`/`PONG` gossip samples, not further `MEET` packets.

#### 2.3.2 `FAIL` (3) — `data.fail`

**Role.** After local `PFAIL` plus majority master reports, broadcast so peers adopt `FAIL` quickly.

**Body** (`clusterMsgDataFail`):

| Field | Size | Content |
|-------|------|---------|
| `about.nodename` | 40 | Node id to mark `FAIL` |

No gossip array; `count` unused.

**Example.** Master `A` promotes `X` to `FAIL` and broadcasts `FAIL` with `about = X`. Peer `D` adopts the flag from known sender `A`.

#### 2.3.3 `PUBLISH` (4) / `PUBLISHSHARD` (10) — `data.publish`

**Role.** Cross-node Pub/Sub. `PUBLISH` is cluster-wide; `PUBLISHSHARD` goes only to other nodes in the sender’s shard.

**Body** (`clusterMsgDataPublish`; lengths in network order):

| Field | Size | Content |
|-------|------|---------|
| `channel_len` | 4 | Channel byte length |
| `message_len` | 4 | Payload byte length |
| `bulk_data` | `channel_len + message_len` | Channel bytes, then message bytes (flexible; struct shows an 8-byte placeholder) |

**Example.** `PUBLISH alerts "disk-full"` on `A` → bus `PUBLISH` to all nodes. `SPUBLISH` → `PUBLISHSHARD` only within the shard.

#### 2.3.4 `FAILOVER_AUTH_REQUEST` (5) — empty `data`

**Role.** Replica asks masters for votes to promote.

**Body.** None beyond the common header. Meaning is in:

| Header / flag | Use in this type |
|---------------|------------------|
| `currentEpoch` / `configEpoch` | Candidate’s election / config epochs |
| `myslots` | Slots the candidate claims |
| `mflags` `FORCEACK` | Manual failover: vote even if master still up |

Broadcast; only slotted masters vote (`clusterSendFailoverAuthIfNeeded`).

**Example.** Replica `R` of failed master `X` broadcasts `FAILOVER_AUTH_REQUEST` with `X`’s former slots in `myslots`.

#### 2.3.5 `FAILOVER_AUTH_ACK` (6) — empty `data`

**Role.** One master’s yes vote, unicast to the candidate.

**Body.** Empty. Validity is the sender being a slotted master and `senderCurrentEpoch >= failover_auth_epoch`. Candidate increments `failover_auth_count`.

**Example.** Master `A` sends `FAILOVER_AUTH_ACK` to `R`; at quorum, `R` promotes.

#### 2.3.6 `UPDATE` (7) — `data.update`

**Role.** Push another node’s slot ownership when a peer’s view is stale.

**Body** (`clusterMsgDataUpdate`):

| Field | Size | Content |
|-------|------|---------|
| `configEpoch` | 8 | Config epoch of the slots owner (network order) |
| `nodename` | 40 | Node id that owns the bitmap |
| `slots` | 2048 | Full 16384-bit slot bitmap for that node |

**Example.** After failover, an `UPDATE` about `R` with a higher epoch rewrites `B`’s slot map so `MOVED` targets `R`.

#### 2.3.7 `MFSTART` (8) — empty `data`

**Role.** Replica asks its master to start manual failover (pause writes, set `mf_end` / `mf_slave`).

**Body.** Empty. Sent from a replica to its master to start manual failover (`mf_end` / `mf_slave` on the master side).

**Example.** `R` sends `MFSTART` to master `M`; `M` pauses clients and pings `R` with the offset for `mf_can_start`.

#### 2.3.8 `MODULE` (9) — `data.module`

**Role.** Opaque module cluster API traffic.

**Body** (`clusterMsgModule`):

| Field | Size | Content |
|-------|------|---------|
| `module_id` | 8 | Module id (endian-safe as stored) |
| `len` | 4 | Payload length (network order) |
| `type` | 1 | Module-defined type 0–255 |
| `bulk_data` | `len` | Opaque payload (flexible; struct shows a 3-byte placeholder) |

**Example.** Module on `A` unicasts or broadcasts a typed blob; `B` dispatches to registered receivers.

### 2.4 Slots and epochs on the wire

Slot ownership and config freshness ride in every gossip **header** (`myslots`, `configEpoch`, `currentEpoch`). When a node learns a **higher** config epoch for a peer’s slots than it currently believes, an `UPDATE` packet’s **body** ([§2.3.6](#236-update-7--dataupdate)) can push that peer’s name, epoch, and full slot bitmap so redirects stay correct after failover or resharding.

### 2.5 Design properties (wire)

| Property | Consequence |
|----------|-------------|
| Separate bus port | Control traffic does not share the client connection pool or RESP parsers |
| Sender header on every packet | Peers continuously refresh reachability and claimed slots |
| Discrete types on same links | One mesh carries both rumor traffic and explicit cluster actions |

Gossip sampling and failure quorum are covered in [§1.2](#12-gossip-mechanism).

### 2.6 Wire format: `clusterMsg`

Binary framing as designed in §2.2. Concrete header fields:

```c
typedef struct {
    char sig[4];              /* "RCmb" */
    uint32_t totlen;
    uint16_t ver;
    uint16_t port;            /* primary client port */
    uint16_t type;            /* CLUSTERMSG_TYPE_* */
    uint16_t count;           /* gossip entries for ping family */
    uint64_t currentEpoch;
    uint64_t configEpoch;
    uint64_t offset;
    char sender[40];
    unsigned char myslots[CLUSTER_SLOTS/8];
    char slaveof[40];
    char myip[NET_IP_STR_LEN];
    uint16_t extensions;
    /* pport, cport, flags, state, mflags, ... */
    union clusterMsgData data;
} clusterMsg;
```

| `CLUSTERMSG_TYPE_*` | Id | `data` content | Example |
|---------------------|----|----------------|---------|
| `PING` / `PONG` / `MEET` | 0–2 | `clusterMsgDataGossip gossip[count]` (+ optional extensions) | [§2.3.1](#231-ping--pong--meet-02--dataping) |
| `FAIL` | 3 | failed node name (`clusterMsgDataFail`) | [§2.3.2](#232-fail-3--datafail) |
| `PUBLISH` / `PUBLISHSHARD` | 4 / 10 | channel + payload lengths and bytes | [§2.3.3](#233-publish-4--publishshard-10--datapublish) |
| `FAILOVER_AUTH_REQUEST` / `ACK` | 5 / 6 | empty beyond header (vote semantics in header/epochs) | [§2.3.4](#234-failover_auth_request-5--empty-data) / [§2.3.5](#235-failover_auth_ack-6--empty-data) |
| `UPDATE` | 7 | config epoch, node name, slots bitmap | [§2.3.6](#236-update-7--dataupdate) |
| `MFSTART` | 8 | empty beyond header | [§2.3.7](#237-mfstart-8--empty-data) |
| `MODULE` | 9 | module id, type, payload | [§2.3.8](#238-module-9--datamodule) |

#### Gossip entry

```c
typedef struct {
    char nodename[CLUSTER_NAMELEN];
    uint32_t ping_sent;
    uint32_t pong_received;
    char ip[NET_IP_STR_LEN];
    uint16_t port;
    uint16_t cport;
    uint16_t flags;
    uint16_t pport;
    uint16_t notused1;
} clusterMsgDataGossip;
```

Optional extensions (`CLUSTERMSG_FLAG0_EXT_DATA`): hostname, human nodename, forgotten-node TTL, shard id, internal secret—8-byte aligned after the gossip array.

### 2.7 Sending: `clusterSendPing`

```c
/* cluster_legacy.c — behavior */
wanted = max(3, floor(dictSize(nodes) / 10));
/* random eligible nodes: not myself, not receiver, not HANDSHAKE/NOADDR/... */
/* then append every PFAIL node */
clusterSetGossipEntry(hdr, gossipcount++, node);
```

| Implementation detail | Purpose |
|-----------------------|---------|
| `wanted ≈ N/10` (min 3) | Probabilistic majority of failure reports within a few timeout windows (see source comment) |
| `last_in_ping_gossip` | Avoid repeating the same node in one ping wave |
| PFAIL appended unconditionally | Faster `PFAIL` → `FAIL` propagation |
| `ping_sent` stamped on outbound `PING` | Local liveness accounting for that peer |

### 2.8 Receiving: `clusterProcessGossipSection`

Called for ping-family packets after length validation.

| Entry | Implementation effect |
|-------|------------------------|
| Corrupt node id | Reject the entire gossip section |
| Known node ≠ myself | Master sender + `PFAIL`/`FAIL` flags → `clusterNodeAddFailureReport`; clear report if gossip says up; `markNodeAsFailingIfNeeded`; may refresh `pong_received` or update address if a down node is reported reachable elsewhere |
| Unknown node | May insert into `server.cluster->nodes` (membership growth via gossip/`MEET`) |

```text
markNodeAsFailingIfNeeded(node):
  require local PFAIL
  failures = reports from masters (+ self if master)
  if failures >= (cluster_size/2)+1
      set FAIL; clusterSendFail(name)
```

### 2.9 Key files

| File | Role |
|------|------|
| `src/cluster_legacy.h` | `clusterMsg`, gossip structs, link/node flags, type ids |
| `src/cluster_legacy.c` | `clusterSendPing`, `clusterProcessGossipSection`, `clusterProcessPacket`, FAIL quorum |
| `src/cluster.h` / `cluster.c` | Slots, redirection, exported cluster API |
| `redis.conf` | `cluster-enabled`, `cluster-node-timeout`, bus announce options |

---

| Topic | Summary |
|-------|---------|
| Architecture | Planes; gossip mechanism (exchange, sampling, failure, promotion) (§1) |
| Implementation | Protocol design (header, data by type); wire structs; send/receive paths (§2) |
