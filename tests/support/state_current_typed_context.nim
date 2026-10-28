# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit authored services accompany newly complete current fixtures; this is supplied inventory, not a producer export.
import std/assertions
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_composition as codec_state_composition
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
