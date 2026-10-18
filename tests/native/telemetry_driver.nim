# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Process-level collector harness driver; all production wire/network logic remains in Nim.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/[os, strutils, assertions, syncio, times, monotimes]
import std/posix/posix
import ../../src/telemetry/[wire, client]

# A tiny deterministic network profile is test data, never a default production chain.
var raw = default(array[MetadataSize, byte])
raw[24] = 2
let parsed = metadata(raw)
var exporter = default(Client)
assert parsed.ok
assert exporter.configure(paramStr(1), parsed.value)
let started = getMonoTime()
var attempt = EventId(0)
var began, settled = false
var identity = default(array[32, byte])
var address = default(array[16, byte])
address[15] = 1
# Bounded lifetime lets the Python collector test success, reset and reconnect without leaking a process.
while (getMonoTime() - started).inMilliseconds < 10000:
  let elapsed = (getMonoTime() - started).inMilliseconds
  exporter.tick(elapsed, Timestamp(uint64(elapsed) * 1000), 7)
  if not began:
    attempt = exporter.dialing(elapsed, Timestamp(uint64(elapsed) * 1000), identity, address, 9000)
    began = true # One attempt precedes the collector reset.
  if elapsed >= 8000 and not settled:
    exporter.dialOutcome(elapsed, Timestamp(uint64(elapsed) * 1000), attempt, true)
    settled = true # Its original ID must still resolve after collector reconnection.
  var request = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(request, remaining) # Driver pacing only; production ticks never sleep.
exporter.close()
echo "telemetry driver ok"
