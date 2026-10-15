## Checked complete-report workload adapter. Setup, preflight and instrumentation are outside timing.
import std/[os, strutils]
import ../src/[composite, work_report, report_owned, owned]
import ../crypto/[primitives, guarantee]

# The common separately compiled, non-LTO observation boundary keeps complete results alive.
proc observe(data: pointer, size: csize_t) {.importc: "rb_observe", cdecl, raises: [].}
# Use the same hardware-resolution monotonic observer in all three benchmark adapters.
proc nowNs(): uint64 {.importc: "rb_now_ns", cdecl, raises: [].}
# Process high-water RSS includes native runtime, prepared corpus and cryptographic providers.
proc peakRss(): uint64 {.importc: "rb_peak_rss", cdecl, raises: [].}

type
  # Prepared immutable input/credentials and typed codec source remain alive across all calls.
  ReportCase = object
    mode: string
    wire, output: seq[byte]
    report: WorkReport
    message: array[46, byte]
    keys: array[2, EdPublicKey]
    signatures: array[2, EdSignature]

# Render exact public preflight bytes; all string work is outside timed and allocation-observation loops.
proc reportHex(bytes: openArray[byte]): string =
  # All prepared reports and guarantee messages are nonempty.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

# Parse a fixed public key/signature token; the trusted fixture loader still checks exact byte width.
proc reportUnhex(text: string): seq[byte] =
  doAssert text.len mod 2 == 0 and text.len <= 128
  result = newSeq[byte](text.len div 2)
  # Exact hexadecimal pairs avoid locale, Unicode and implicit truncation in adapter inputs.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Verify both distinct ordinary-key credentials, preserving the pinned backend's actual verdict.
proc reportVerify(item: ReportCase, message: openArray[byte]): bool {.raises: [].} =
  let first = verify(item.keys[0], item.signatures[0], message)
  let second = verify(item.keys[1], item.signatures[1], message)
  first and second

# One real operation with identical checks/opaque observation boundaries; no fixture or IPC cost is timed.
proc reportStep(item: var ReportCase): uint64 {.noinline, raises: [].} =
  case item.mode
  of "decode":
    # Observe the complete typed result, preventing unused fields from being optimized away.
    var decoded = decodeReportBorrowed(item.wire, 341)
    doAssert decoded.error == CompositeError.None and decoded.consumed == item.wire.len
    observe(addr decoded, csize_t(sizeof(decoded)))
  of "encode":
    # Source metadata is prepared once; this stage measures independent checked report serialization.
    let written = encodeReportBorrowed(item.report, item.wire, 341, item.output)
    doAssert written.error == CompositeError.None and written.written == item.wire.len
    observe(addr item.output[0], csize_t(written.written))
  of "owned", "pipeline":
    # Capture, use and final ARC release all belong to this operation's measured lifetime.
    let captured = decodeOwnedReport(item.wire, 341)
    doAssert captured.error == OwnershipError.None
    let written = encodeOwnedReport(captured.value, item.output)
    doAssert written.error == OwnershipError.None and written.value == item.wire.len
    observe(addr item.output[0], csize_t(written.value))
    if item.mode == "pipeline":
      # Complete canonical owned bytes feed the normative hash/domain and two-credential verification.
      var message = guaranteeMessage(item.output)
      doAssert message.error == CryptoError.None
      var bytes = array[46, byte](message.value)
      doAssert reportVerify(item, bytes)
      observe(addr bytes[0], 46)
  of "hash":
    # This stage includes the actual provider plus the small native normative domain composition.
    var message = guaranteeMessage(item.wire)
    doAssert message.error == CryptoError.None
    observe(addr message, csize_t(sizeof(message)))
  of "verify2":
    # Prepared message excludes report hashing so provider verification cost can be distinguished.
    var valid = reportVerify(item, item.message)
    doAssert valid
    observe(addr valid, csize_t(sizeof(valid)))
  else: doAssert false # Unregistered operation names cannot generate successful timings.
  uint64(item.wire.len)

# Run one bounded native process; verification mode accepts invalid signatures only to report their false verdict.
proc reportBenchmark*() =
  doAssert paramCount() == 10
  var item = ReportCase(mode: paramStr(2))
  let text = readFile(paramStr(3))
  doAssert text.len <= 65536
  item.wire = newSeq[byte](text.len)
  # File loading is native and untimed; the resulting bytes have one stable owner.
  for i in 0..<text.len: item.wire[i] = byte(text[i])
  let parsed = decodeReportBorrowed(item.wire, 341)
  doAssert parsed.error == CompositeError.None and parsed.consumed == item.wire.len
  item.report = parsed.value
  item.output = newSeq[byte](item.wire.len)
  let encoded = encodeReportBorrowed(item.report, item.wire, 341, item.output)
  doAssert encoded.error == CompositeError.None and encoded.written == item.wire.len and
      item.output == item.wire
  # Import two distinct public credentials before measurement; no key parsing is charged to verification.
  for i in 0..<2:
    let key = importPublicKey(reportUnhex(paramStr(4+2*i)))
    let signature = importSignature(reportUnhex(paramStr(5+2*i)))
    doAssert key.error == CryptoError.None and signature.error == CryptoError.None
    item.keys[i] = key.value; item.signatures[i] = signature.value
  let message = guaranteeMessage(item.wire)
  doAssert message.error == CryptoError.None
  item.message = array[46, byte](message.value)
  let valid = reportVerify(item, item.message)
  echo "VERIFY ", reportHex(item.output), " ", reportHex(item.message), " ", ord(valid)
  if item.mode == "check": return # Negative credential tests stop before any timing operation.
  doAssert valid
  let iterations = parseInt(paramStr(8))
  let samples = parseInt(paramStr(9))
  let latency = parseInt(paramStr(10))
  doAssert iterations in 1..20000000 and samples in 1..31 and latency in 0..256
  var checksum: uint64
  # Warm runtime, allocator, provider and code paths identically before observing anything.
  for i in 0..<min(iterations, 64): checksum = checksum xor reportStep(item)
  when defined(nimAllocStats):
    # Instrumentation has a separate binary and never produces throughput/latency samples.
    let before = getAllocStats()
    let live = getOccupiedMem()
    for i in 0..<iterations: checksum = checksum xor reportStep(item) # Count only post-warmup operations.
    let after = getAllocStats()-before
    echo "ALLOC_NIM ", iterations, " ", getOccupiedMem()-live, " ", after
  else:
    # Batch averages amortize timer overhead but remain distinct from individual latency samples.
    for sample in 0..<samples:
      let start = nowNs()
      for i in 0..<iterations: checksum = checksum xor reportStep(
          item) # Identical operation counts for all candidates.
      echo "BATCH ", iterations, " ", nowNs()-start
    var latencies = newSeq[uint64](latency)
    for i in 0..<latency:
      # One operation per sample includes the same timer/observer overhead in every language.
      let start = nowNs()
      checksum = checksum xor reportStep(item)
      latencies[i] = nowNs()-start
    for elapsed in latencies: echo "LATENCY ", elapsed # Printing happens after individual samples finish.
  echo "END ", checksum, " ", peakRss()
