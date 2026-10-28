# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated external-input capture failures must reject success-payload extraction.

import std/cmdline
import ../../src/pvm/host_fetch as pvm_host_fetch
let base = captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
  FetchPresence.Absent, [], FetchTraceLimit(0)).value
case paramStr(1)
of "context":
  # No external-input selection may repair an uninitialized base.
  discard withFetchInputs(default(FetchContext), FetchInputs(), FetchInputLimit(0)).value
of "current":
  # A present current item must index each selected table.
  let source = FetchInputs(extrinsicsPresence: FetchPresence.Present,
    currentPresence: FetchPresence.Present, current: FetchItemIndex(high(uint64)))
  discard withFetchInputs(base, source, FetchInputLimit(0)).value
of "count":
  # Zero-byte preimages still consume bounded metadata entries.
  let source = FetchInputs(extrinsicsPresence: FetchPresence.Present,
    extrinsics: @[newSeq[seq[byte]](129)])
  discard withFetchInputs(base, source, FetchInputLimit(0)).value
else:
  # A short aggregate cap exposes no partly captured input snapshot.
  let source = FetchInputs(extrinsicsPresence: FetchPresence.Present, extrinsics: @[@[@[1'u8]]])
  discard withFetchInputs(base, source, FetchInputLimit(0)).value
