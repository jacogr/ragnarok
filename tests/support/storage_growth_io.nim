# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only SDK counters use a separate build; ordinary performance runs compile these calls away.
when defined(storageIoCounts):
  import std/syncio
  import ./storage_io

proc beginGrowthIo*() {.inline.} =
  ## Reset counters and leave every refusal/short-progress control disarmed before a measured operation.
  when defined(storageIoCounts):
    resetIo()
  else:
    discard # Ordinary speed measurements link no observer and execute no SDK counting.
proc endGrowthIo*(engine: string, count, publications: int, pattern: string, sample: int,
    phase: string) {.inline.} =
  ## Snapshot counters before output can perform IO; only the separate observed executable emits them.
  when defined(storageIoCounts):
    let observed = [ioCalls(readIo), ioCalls(writeIo), ioCalls(syncIo), ioCalls(truncateIo),
      ioCalls(lockIo), ioCalls(renameIo), ioCalls(unlinkIo), ioCalls(closeIo)]
    echo "io\t", engine, "\t", count, "\t", publications, "\t", pattern, "\t", sample,
      "\t", phase, "\t", observed[0], "\t", observed[1], "\t", observed[2], "\t",
      observed[3], "\t", observed[4], "\t", observed[5], "\t", observed[6], "\t", observed[7]
  else:
    discard # Timing/report success never accepts observed-profile latency values.
