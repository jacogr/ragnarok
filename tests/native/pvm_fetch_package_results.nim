# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated package-fetch capture misuse probes reject failed context payload extraction.

import std/cmdline
import ../../src/codec/[work_package, bounded]
import ../../src/pvm/host_fetch
let base = captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
  FetchPresence.Absent, [], FetchTraceLimit(0)).value
case paramStr(1)
of "context":
  # Even an absent package cannot repair an invalid base context.
  discard withFetchPackage(default(FetchContext), FetchPresence.Absent,
    default(OwnedWorkPackage), FetchPackageLimit(0), FetchEncodingLimit(32768)).value
of "owner":
  # A present default codec owner must not become a successful absent package.
  discard withFetchPackage(base, FetchPresence.Present, default(OwnedWorkPackage),
      FetchPackageLimit(0), FetchEncodingLimit(32768)).value
else:
  # Construct a valid owner before testing either independent capture budget.
  let value = WorkPackage(items: @[WorkItem(payload: @[1'u8])])
  var wire = default(array[1024, byte])
  let config = fullPackageConfig(ByteLimit(1024))
  let size = encodeWorkPackage(value, config, wire).value
  let package = decodeWorkPackage(wire.toOpenArray(0, size - 1), config).value.owner
  if paramStr(1) == "encoding":
    # A short encoding budget exposes no context even when all raw blobs fit.
    discard withFetchPackage(base, FetchPresence.Present, package, FetchPackageLimit(1),
        FetchEncodingLimit(0)).value
  else:
    # Preserve the independent aggregate raw-blob refusal probe.
    discard withFetchPackage(base, FetchPresence.Present, package, FetchPackageLimit(0),
        FetchEncodingLimit(32768)).value
