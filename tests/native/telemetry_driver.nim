## Process-level collector harness driver; all production wire/network logic remains in Nim.
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
# Bounded lifetime lets the Python collector test success, reset and reconnect without leaking a process.
while (getMonoTime() - started).inMilliseconds < 10000:
  let elapsed = (getMonoTime() - started).inMilliseconds
  exporter.tick(elapsed, Timestamp(uint64(elapsed) * 1000), 7)
  var request = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(request, remaining) # Driver pacing only; production ticks never sleep.
exporter.close()
echo "telemetry driver ok"
