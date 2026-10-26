# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deterministic bounded-output, disabled-formatting, overload, restart and producer lifetime checks.
import std/[assertions, syncio, locks, os, strutils, rawthreads]
import ../../../src/lib/logging

type Capture = object ## Only the writer mutates bytes; the host observes them after joined close.
  lock: Lock
  changed: Cond
  entered, releaseSink, blocking: bool
  text: string

proc collect(raw: nil pointer, batch: string) {.raises: [].} =
  ## A controlled slow sink makes a blocking producer implementation deadlock deterministically.
  let capture = cast[ptr Capture](raw)
  acquire(capture.lock)
  capture.entered = true
  signal(capture.changed)
  while capture.blocking and not capture.releaseSink: wait(capture.changed, capture.lock)
  release(capture.lock)
  capture.text.add(batch)

proc accepted(writer: LogWriter, message: string) =
  ## Retry only in this test to arrange a known accepted record despite a busy startup lock.
  for attempt in 0..<1000:
    if submitLog(writer, LogTarget.Pvm, LogLevel.Info, message): return
    sleep(1)
  assert false, "test admission deadline"

proc capture(): Capture =
  ## Synchronization is initialized only after this movable plain value reaches its final address.
  Capture(entered: false, releaseSink: false, blocking: false, text: "")

func lines(text: string): int =
  ## Count physical newlines without relying on extra stdlib string helpers.
  result = 0
  for character in text:
    if character == '\n': inc result

var policy = default(LogPolicy)
assert parseLogPolicy("info,pvm=trace,network=warn", policy)
assert policy.threshold(LogTarget.Pvm) == LogLevel.Trace
assert policy.threshold(LogTarget.Network) == LogLevel.Warn
assert policy.threshold(LogTarget.Rpc) == LogLevel.Info
assert parseLogPolicy("pvm=debug", policy)
assert policy.threshold(LogTarget.Rpc) == LogLevel.Info
for invalid in ["", "INFO", "debug,info", "info,", "info,pvm=", "pvm=bad", "unknown=info",
    "pvm=info,pvm=trace", "pvm=info,off", " info", "info,pvm=debug=trace"]:
  assert not parseLogPolicy(invalid, policy)
  for index in 0..ord(high(LogTarget)): assert policy.threshold(LogTarget(index)) == LogLevel.Off

var logger = default(Logger)
var observed = capture()
initLock(observed.lock)
initCond(observed.changed)
assert start(logger, initLogPolicy(LogLevel.Off), collect, addr observed)
let disabled = logger.writer
var formatted = 0
for index in 0..<10000:
  log(disabled, LogTarget.Pvm, LogLevel.Info, block:
    inc formatted
    "should never be constructed")
assert formatted == 0 and logger.stats.accepted == 0 and logger.stats.dropped == 0
close(logger)
assert observed.text.len == 0
assert not disabled.enabled(LogTarget.Pvm, LogLevel.Fatal)
var quietStartup = default(LogPolicy)
assert parseLogPolicy("trace,startup=off", quietStartup)
assert start(logger, quietStartup, collect, addr observed)
assert not disabled.enabled(LogTarget.Pvm, LogLevel.Fatal) # Prior-generation handles cannot reenter a restarted sink.
let output = logger.writer
accepted(output, "hello\n\x1b" & repeat("x", 8192))
close(logger)
assert observed.text.startsWith("[info][pvm] hello\\x0a\\x1b")
assert observed.text.endsWith("...[truncated]\n")
assert observed.text.len <= LogRecordBytes and lines(observed.text) == 1
assert logger.stats.processed == 1

# Occupy the sink after it has released the queue lock, then fill every finite queue slot.
observed.text = ""
observed.entered = false
observed.releaseSink = false
observed.blocking = true
assert start(logger, initLogPolicy(), collect, addr observed)
let queued = logger.writer
accepted(queued, "first")
let startupDrops = logger.stats.dropped
acquire(observed.lock)
while not observed.entered: wait(observed.changed, observed.lock)
release(observed.lock)
var admissions = 0
for index in 0..<LogQueueCapacity+31:
  if submitLog(queued, LogTarget.Pvm, LogLevel.Info, "queued-" & $index): inc admissions
assert admissions == LogQueueCapacity
assert logger.stats.accepted == uint64(LogQueueCapacity+1)
assert logger.stats.dropped == startupDrops+31
acquire(observed.lock)
observed.releaseSink = true
signal(observed.changed)
release(observed.lock)
close(logger)
assert logger.stats.processed == logger.stats.accepted
assert lines(observed.text) == LogQueueCapacity+2
assert "queued-255\n" in observed.text and "queued-256\n" notin observed.text
assert logger.stats.batches < logger.stats.processed # Backlog becomes bounded multi-record writes.

type Producer = object ## Handles are plain borrows; every producer joins before logger retirement.
  writer: LogWriter
  accepted: int
proc produce(raw: pointer) =
  ## Both native producers contend with each other and the consumer using the public API.
  let producer = cast[ptr Producer](raw)
  for index in 0..<200:
    if submitLog(producer.writer, LogTarget.Network, LogLevel.Info, "parallel-" & $index):
      inc producer.accepted

observed.text = ""
observed.blocking = false
assert start(logger, initLogPolicy(), collect, addr observed)
var producers = [Producer(writer: logger.writer, accepted: 0),
    Producer(writer: logger.writer, accepted: 0)]
var first, second: RawThread
var firstStarted = false
try:
  first.create(produce, addr producers[0])
  firstStarted = true
  second.create(produce, addr producers[1])
except:
  if firstStarted: first.join()
  close(logger)
  assert false, "test thread creation failed"
first.join()
second.join()
close(logger)
assert logger.stats.accepted+logger.stats.dropped == 400
assert logger.stats.accepted == uint64(producers[0].accepted+producers[1].accepted)
assert logger.stats.processed == logger.stats.accepted
assert uint64(lines(observed.text)) == logger.stats.processed+uint64(if logger.stats.dropped > 0: 1 else: 0)
deinitCond(observed.changed)
deinitLock(observed.lock)
close(logger)
echo "Shared logging passed"
