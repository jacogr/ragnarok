## Each subprocess deliberately reads one success-only bounded result member after failure/default.
import ../../src/codec/[bounded, fixed_unsigned]
import std/[cmdline, syncio]
# Runtime fixture selection prevents one statically known default from rejecting the whole test build.
let useDefault = paramStr(2) == "default"
let empty = newSeq[byte](0)
var output = newSeq[FixedUnsigned](0)
var wire = newSeq[byte](0)
let blob = if useDefault: default(BlobResult) else: decodeBytesBorrowed(empty, ByteLimit(1))
let written = if useDefault: default(WriteResult) else: encodeBytes([byte(1)], ByteLimit(0), wire)
let sequence = if useDefault: default(SequenceResult) else: decodeSequence(empty,
    ByteWidth(1), ElementLimit(1), output)
# Every branch calls a distinct public accessor; any successful read would violate the API contract.
case paramStr(1)
of "offset":
  # Failed blobs cannot reveal a default payload start.
  echo blob.offset
of "length":
  # Failed blobs cannot masquerade as validated empty payloads.
  echo blob.length
of "blob-consumed":
  # Failed blobs cannot advance a caller's byte cursor.
  echo blob.consumed
of "written":
  # Failed writes cannot report committed bytes.
  echo written.written
of "count":
  # Failed sequences cannot authorize any initialized output prefix.
  echo sequence.count
of "sequence-consumed":
  # Failed sequence reads cannot publish partial progress.
  echo sequence.consumed
else:
  # A misspelled mode is a fixture error, never evidence of a working result guard.
  quit 2
