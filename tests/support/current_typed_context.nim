# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit authored services accompany newly complete current fixtures; this is supplied inventory, not a producer export.
import std/assertions
import ../../src/state/store
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, accounts as state_accounts,
    composition as state_composition]
proc currentSuppliedServices*(source: StateStoreSnapshot): seq[StateService] =
  ## Authored no-execution/no-blob fixtures name services 42/99 and empty child maps; whole-map matching must verify completeness.
  result = @[]
  for id in [42'u32, 99'u32]:
    let service = ServiceIndex(id)
    let raw = source.lookup(chapterServiceKey(StateChapter(255), service)).value.bytes
    let decoded = decodeServiceMetadata(raw, ByteLimit(105))
    assert decoded.error == ServiceMetadataError.None
    assert decoded.value.consumed == raw.len
    result.add(StateService(service: service, metadata: decoded.value.metadata))
