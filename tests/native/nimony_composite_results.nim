## Runtime-selected result, nested-variant and explicit-constructor misuse must reject before reading data.
import ../../src/codec/[composite, bounded, work_digest]
import std/[cmdline, syncio]

# Select the six real payload-free work tags without accepting an accidental fixture spelling.
proc workError(text: string): WorkKind =
  case text
  of "1": WorkKind.OutOfGas # Exact wire tag one.
  of "2": WorkKind.Panic # Exact wire tag two.
  of "3": WorkKind.BadExports # Exact wire tag three.
  of "4": WorkKind.Oversize # Exact wire tag four.
  of "5": WorkKind.Bad # Exact wire tag five.
  of "6": WorkKind.Big # Exact wire tag six.
  else: quit 2 # Fixture mistakes are never contract evidence.

# Unknown runtime origin keeps both actual error and default paths in one executable.
let useDefault = paramStr(2) == "default"
let empty = newSeq[byte](0)
var output = newSeq[byte](0)
var records = newSeq[Preimage](0)
let limits = PreimageLimits(items: ElementLimit(1), perBlob: ByteLimit(1),
    totalBlobBytes: ByteLimit(1))
let optional = if useDefault: default(OptionalResult) else: decodeOptionalBorrowed(empty, ByteLimit(1))
let work = if useDefault: default(WorkResult) else: decodeWorkBorrowed(empty, ByteLimit(1))
let preimages = if useDefault: default(PreimageResult) else: decodePreimagesBorrowed(empty, limits, records)
let written = if useDefault: default(CompositeWrite) else: encodePreimagesBorrowed(records, empty,
    limits, output)
let digest = if useDefault: default(DigestResult) else: decodeDigestBorrowed(empty, ByteLimit(1))
case paramStr(1)
of "optional-value":
  # A failed optional has no variant to inspect.
  echo optional.value.present
of "optional-consumed":
  # A failed optional has no prefix progress.
  echo optional.consumed
of "work-value":
  # A failed work-output decode cannot expose a default Success tag.
  echo ord(work.value.kind)
of "work-consumed":
  # A failed work-output decode cannot advance a cursor.
  echo work.consumed
of "preimages-count":
  # A failed scan cannot authorize any caller-owned records.
  echo preimages.count
of "preimages-consumed":
  # A failed record sequence cannot expose partial progress.
  echo preimages.consumed
of "written":
  # Failed encoders cannot report committed output.
  echo written.written
of "digest-value":
  # A failed digest cannot expose a default service identity.
  echo uint32(digest.value.service)
of "digest-consumed":
  # A failed digest cannot expose a prefix extent.
  echo digest.consumed
of "absent-blob":
  # Both default and explicitly absent optionals lack spans, independently of result success.
  let absent = if useDefault: default(OptionalBlob) else: absentBlob()
  echo absent.blob.length
of "error-work-blob":
  # Every one of the six valid work-error tags has no readable payload span.
  echo failedWork(workError(paramStr(2))).blob.length
of "factory-work":
  # Payload-free construction may never manufacture the Success alternative.
  let tag = if paramStr(2) == "success": WorkKind.Success else: WorkKind.OutOfGas
  echo ord(failedWork(tag).kind)
of "factory-written":
  # A completed encoder extent cannot be negative.
  let extent = if paramStr(2) == "negative": -1 else: 0
  echo compositeWritten(extent).written
of "factory-failure":
  # A failure constructor cannot manufacture a None/success result with no extent.
  let reason = if paramStr(2) == "none": CompositeError.None else: CompositeError.Truncated
  echo ord(compositeFailure(reason).error)
else:
  # A misspelled mode must not be counted as a guarded accessor rejection.
  quit 2
