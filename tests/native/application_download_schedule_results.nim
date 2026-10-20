# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic default/refused extraction must trip the actual optimized runtime contract.
import std/cmdline
import ../../src/app/download_schedule
import ../../src/codec/bounded
let mode = paramStr(1)
var schedule = default(DownloadSchedule)
let selection = if mode == "default": default(DownloadSelection)
  else: schedule.select(DownloadScheduleTick(0))
if mode == "peer":
  discard default(DownloadAttempt).peer # No peer ID belongs to an absent lease.
elif mode == "positive":
  discard schedule.configure([DownloadPeerId(1)], DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(1)), DownloadScheduleTick(0))
  discard schedule.select(DownloadScheduleTick(0)).value.peer # Real success remains usable.
else:
  discard selection.value # An uninitialized plan cannot authorize a stream.
