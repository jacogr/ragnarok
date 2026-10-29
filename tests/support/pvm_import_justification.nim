# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed independent inclusion witnesses and finite verification policies.

import "../../src/state/import/justification" as import_justification
import ../../src/codec/bounded
import ../../src/codec/work/report as work_report
import ../../src/pvm/host_fetch

proc importLimits*(): ImportJustificationLimits =
  ## Admit the full twelve-sibling GP domain with separately bounded copying and hash preimages.
  ImportJustificationLimits(siblings: ElementLimit(12), payloadBytes: ByteLimit(4488),
      hashBytes: ByteLimit(4924))
proc importPath*(values: openArray[array[32, byte]]): seq[SegmentRoot] =
  ## Capture immutable oracle octets into the required nominal tree hash domain for calls under test.
  result = newSeq[SegmentRoot](values.len)
  for index in 0..<values.len: result[index] = SegmentRoot(bytes: values[index])
proc importSegment*(first = 0'u8): FetchSegment =
  ## Literal first-byte variations distinguish sibling direction and index without invoking production hashing.
  var bytes = default(array[4104, byte])
  bytes[0] = first
  FetchSegment(bytes)
