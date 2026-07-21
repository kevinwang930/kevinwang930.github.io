---
title: "Redis Build from Source"
date: 2026-07-18T10:38:29+07:00
categories:
- data
- cache
tags:
- data
- cache
- redis
keywords:
- redis
- cache
#thumbnailImage: //example.com/image.jpg
---
Build Redis from source on Fedora and debug `redis-server` in CLion. Architecture notes: [Redis internals](architecture/), [Pub/Sub](pubsub/), [Cluster bus](cluster-bus/).

<!--more-->

## Dependencies

```bash
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y gcc make openssl-devel
```

`openssl-devel` is required only for `BUILD_TLS=yes`.

## Debug build

The default Makefile build uses `-O3` and LTO (`-flto=auto`). LTO breaks GDB line-to-address mapping, so source breakpoints on `processCommand` often miss while the process still answers `PING`.

Build with `-O0` (disables LTO):

```bash
cd /path/to/redis
make distclean
make OPTIMIZATION=-O0 -j"$(nproc)"
```

Optional TLS:

```bash
make BUILD_TLS=yes OPTIMIZATION=-O0 -j"$(nproc)"
```

Confirm flags in `src/.make-settings`: `PREV_FINAL_CFLAGS` must contain `-O0` and must not contain `-flto`. Change of `OPTIMIZATION` requires `make distclean` before rebuilding.

Binaries: `src/redis-server`, `src/redis-cli`.

## CLion

Open the repository as a **Makefile** project (not CMake). Use the system GCC toolchain and GDB.

**Run → Edit Configurations → Native Application:**

| Field | Value |
|--------|--------|
| Executable | `<redis>/src/redis-server` |
| Program arguments | `redis.conf --port 6380` |
| Working directory | `<redis>` |

Start with **Debug**. Stop any prior instance on port 6380. Trigger command execution from another terminal:

```bash
src/redis-cli -p 6380 PING
```

Breakpoints for the command path: `processCommand`, `call`, `pingCommand` in `server.c`. These run only after a client command; startup alone does not enter them.

If Make fails on a stale `fast_float` include path:

```bash
rm -f src/*.d src/Makefile.dep src/.make-*
make distclean
make OPTIMIZATION=-O0 -j"$(nproc)"
```

## Compilation database

For navigation, generate `compile_commands.json` with the same flags:

```bash
sudo dnf install -y bear
cd /path/to/redis
make distclean
bear -- make OPTIMIZATION=-O0 -j"$(nproc)"
```

Point CLion at `<redis>/compile_commands.json`.
