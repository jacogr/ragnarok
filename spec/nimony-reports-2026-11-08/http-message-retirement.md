# NIM-009: retained storage after retiring HTTP messages

Status: draft investigation, pending retest on the planned newer Nimony. No issue filed.
Last tested: November 8, 2026; official Nimony 0.6.3 archive at
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, macOS ARM64, `nimony c`, checked release,
ARC/Clang/ThinLTO. No compiler or library files were modified.

## Reproduction and output

The complete standalone source is [http-message-retirement.nim](http-message-retirement.nim).
It creates exactly one shared process vocabulary, then parses and retires fresh messages.
It imports only standard library modules and uses no application code, sockets or raw ownership
hooks. Ten warm-up requests precede the measured hundred.

```nim
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standalone pinned-library retirement probe; not a passing application test or submitted issue.
import std/[assertions, syncio]
import std/http/httpmsg as msg
import std/http/httpparse as parser

let tags = msg.newHttpTags() # One shared vocabulary for the process, as documented.

proc parseOne() =
  var head = msg.initHttpMsg(tags)
  let wire = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
  assert parser.parseRequestHead(toOpenArray(wire, 0, wire.len - 1), head) == wire.len
  assert head.getStr(msg.hHost) == "localhost"

for index in 0..<10: parseOne()
let baseline = getOccupiedMem()
for index in 0..<100: parseOne()
let retained = getOccupiedMem() - baseline
echo "retained bytes after 100 retired messages: ", retained
assert retained <= 256, "retired HTTP messages release their owned storage"
```

Run in an empty directory with a copy of that source and a fresh cache:

```
<nimony>/bin/nimony c --mm:arc --cc:clang -d:release --opt:speed --boundchecks:on --passC:-flto=thin --passL:-flto=thin --nimcache:<fresh-cache> --out:probe probe.nim
./probe
```

Five independent fresh-directory builds succeeded; each runtime exited 1 with exactly:

```
retained bytes after 100 retired messages: 20800
[Assertion Failure] retired HTTP messages release their owned storage
```

Commands, outputs and exit codes are retained in
`build/ci/rpc3-http-shared-retirement-probe.json` and the corresponding
`build/probes/http-cleanup/shared-fresh-*/` directories. These are pinned macOS results, not
Linux execution of the standalone source or current-upstream qualification.

## Controls and attribution

The original application created new `HttpTags` per request, whereas `newHttpTags` documents one
vocabulary initialized and shared by the application. That usage was inefficient and the first
reproducer retained 227,200 bytes per hundred requests. The source above corrects that usage;
20,800 bytes still remain after message retirement.

Additional same-pin controls recorded in `build/probes/http-cleanup/`:

- Creating and retiring 100 tag spaces alone retains 0 bytes.
- With one shared vocabulary, constructing and retiring 100 empty `HttpMsg` owners retains
  11,200 bytes, without parsing or inspecting any request.
- Reusing a message with `reset()` is flat during its lifetime. Retiring ten owners after each
  handled 100 requests still retains 2,080 bytes. Recycling reduces per-request growth but is
  not proof that the owner releases its storage.

`HttpMsg` documents a move-only message with an owned literal pool that dies with it.
The inspected `TokenBuf` contains owning `pool`, `tags` and `openTags` fields, but its custom
`=destroy` only releases the cursor owner or raw token data. The pinned generated C shows the
same cleanup and does not release those fields. This is the leading ownership attribution;
no library patch was made to claim a verified upstream fix. The exact compiler/library stage
responsible must be rechecked on the new pin before submitting upstream.

## Application impact and next action

Master `3e5ac98faa05a8bba18406f4bc019f97fd86a4bc` completed its RPC/browser exchanges but
failed the existing cleanup gate: `SERVICE_CLEAN 15088 92032`. The failing
[E2E / Testnet job](https://github.com/jacogr/ragnarok/actions/runs/42487188660/job/128751519252)
retains the traceback at `tests/rpc_checks.py`'s zero-exit assertion and peer/browser logs.
The repair temporarily rolls back stock HTTP adoption without changing the cleanup allowance.
A normal UI test now requires flat memory across repeated request-owner retirement.

The upstream issue search `TokenBuf leak` found no match on November 8. Current upstream source
at `ad334fb80c031da5b9932e3f254c23b6dd5ccbe1` was inspected; its runtime/compiler was **not run**.
Retest the standalone source and complete consumer lifecycle after the planned upgrade, search
again, and file upstream only if the problem persists. This draft is not ready for submission.
