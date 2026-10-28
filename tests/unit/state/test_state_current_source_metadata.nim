# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unmodified pinned release metadata is not current metadata; explicit test-only expansion remains derived evidence.
import std/assertions
import std/envvars
import std/strutils
import std/syncio
import std/parseutils
import ../../support/state_complete_serialization_context
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
proc main() {.raises.} =
  ## Check every exact historical/derived pair without adding a production decoder fallback.
  var count = 0
  for line in readFile(getEnv("RAGNAROK_CURRENT_SOURCE_METADATA")).splitLines():
    if line.len == 0: continue # The pinned transport ends in a newline.
    let fields = line.splitWhitespace()
    assert fields.len == 3
    var rawId = 0'u64
    assert parseBiggestUInt(fields[0], rawId) == fields[0].len
    assert rawId <= uint64(high(uint32))
    let service = ServiceIndex(uint32(rawId))
    let raw = serializationOctets(fields[1])
    let derived = serializationOctets(fields[2])
    assert raw.len == 89 and derived.len == 105
    assert decodeServiceMetadata(raw, ByteLimit(105)).error == ServiceMetadataError.Truncated
    let decoded = decodeServiceMetadata(derived, ByteLimit(105))
    assert decoded.error == ServiceMetadataError.None
    assert decoded.value.consumed == 105
    let metadata = decoded.value.metadata
    assert uint32(metadata.supervisor) == 0
    assert uint32(metadata.supervisorCreated) == 0
    assert uint64(metadata.supervisorBalance) == 0
    let entry = serviceMetadataEntry(service, metadata, ByteLimit(105)).value
    assert entry.value == derived
    assert array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255), service))
    inc count
  assert count == 26
  echo "state-current-source-metadata: ok (26 pairs)"
try:
  main()
except:
  quit(2) # Source provenance/setup failure never qualifies a current-schema metadata observation.
