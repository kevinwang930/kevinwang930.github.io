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
How to build Redis from source on Fedora, configure a non-default port, and open the tree in CLion. For architecture and data types, see the [Redis internals overview](architecture/).
<!--more-->

# Build Redis from source (Fedora)

Building from source is useful when you need a specific Redis version, TLS, or build flags that the Fedora package does not provide. Redis itself depends mainly on a C toolchain and `libc`; optional TLS needs OpenSSL development headers. Tests need Tcl.

## Install build dependencies

```bash
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y gcc make openssl-devel tcl wget
```

`Development Tools` provides `gcc`, `make`, and related utilities. `openssl-devel` is required only if you build with TLS (`BUILD_TLS=yes`). `tcl` is required for `make test`.


## Compile

Default build (binaries land under `src/`):

```bash
make -j"$(nproc)"
```

With TLS:

```bash
make BUILD_TLS=yes -j"$(nproc)"
```

Optional: run the test suite (needs `tcl`):

```bash
make test
```

If the tree was previously built with different flags, clean first:

```bash
make distclean
make -j"$(nproc)"
```

## Install and verify

Install into `/usr/local/bin` by default:

```bash
sudo make install
redis-server --version
redis-cli --version
```

Foreground smoke test:

```bash
redis-server
# another terminal
redis-cli ping   # expect PONG
```

Stop with `Ctrl-C` in the server terminal. For a long-running install, copy `redis.conf` (for example from the source tree) under `/etc/redis/` and add a systemd unit; a from-source install does not create a Fedora `redis.service` automatically.

# Configure CLion for the Redis source tree

Redis is a Makefile project: there is no root `CMakeLists.txt`. Open the repository as a Makefile project, build with Make, then attach Run/Debug configurations to the binaries under `src/`.

## Open as a Makefile project

**File → Open** the Redis repository root. When prompted, choose **Open as Makefile project** (not CMake).

If the project was opened as CMake by mistake: close it, then reopen and select the Makefile option.

Build once from a terminal so `deps/` and `src/redis-server` exist before debugging:

```bash
cd /path/to/redis
make -j"$(nproc)"
```

If Make fails with a missing path such as `../deps/fast_float/fast_float_strtod.h`, stale dependency files are usually the cause. Clear them and rebuild:

```bash
rm -f src/*.d src/Makefile.dep src/.make-*
make distclean
make -j"$(nproc)"
```

## Toolchain

Under **Settings → Build, Execution, Deployment → Toolchains**, use the system GCC toolchain and GDB (or LLDB). On Fedora, this matches the same `gcc` / `make` stack used for the command-line build.

## Run and debug `redis-server`

**Run → Edit Configurations → + → Native Application** (or Makefile Application if offered):

| Field | Value |
|--------|--------|
| Executable | `<redis>/src/redis-server` |
| Program arguments | `<redis>/redis.conf --port 6380` |
| Working directory | `<redis>` |

If a system `redis` service already owns **6379**, do not use the default port for a from-source debug instance. Pass a conf file and a port override together; CLI options after the conf path override matching settings in the file:

```bash
# server: load redis.conf, then force port 6380
src/redis-server redis.conf --port 6380
# client
src/redis-cli -p 6380 ping
```

In CLion, use the same server Program arguments (`redis.conf --port 6380`, or an absolute path to the conf). Add a second configuration for `<redis>/src/redis-cli` with `-p 6380`. You can instead set `port 6380` inside a copied conf and pass only that file; using both is useful when you want the rest of `redis.conf` unchanged.

Rebuild with **Build → Build Project** or `make -j"$(nproc)"` so debug symbols match the sources before a session.

TLS builds use the same CLion setup after compiling with `make BUILD_TLS=yes`; ensure `openssl-devel` is installed.

## Code insight (`compile_commands.json`)

Makefile indexing alone is often incomplete for jump-to-definition. Generate a compilation database with Bear:

```bash
sudo dnf install -y bear
cd /path/to/redis
make distclean
bear -- make -j"$(nproc)"
```

Point CLion’s compilation database / Clangd settings at `<redis>/compile_commands.json`. Useful include roots if you add paths manually: `src`, `deps/hiredis`, `deps/lua/src`, and `deps/jemalloc/include` when using jemalloc.

Mark large dependency trees you do not edit (for example most of `deps/jemalloc`) as **Excluded** to keep indexing faster.


```



