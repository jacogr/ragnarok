## Verify complete report bytes and independently supplied guarantee credentials without timing code.
import std/[os, strutils]
import ../../src/codec/[composite, work_report]
import ../../src/crypto/[primitives, guarantee]

# Render every public byte so the Python fixture oracle can check exact transcript construction.
proc reportHex(bytes: openArray[byte]): string =
  # Reports and their signing messages are nonempty and retain identity byte order.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

# Import bounded public fixture encodings; production secrets never enter this test adapter.
proc reportUnhex(text: string): seq[byte] =
  doAssert text.len mod 2 == 0 and text.len <= 128
  result = newSeq[byte](text.len div 2)
  # Each complete hexadecimal pair becomes one owned public byte.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Decode/re-emit a complete report and verify two credentials over its normative signing message.
proc reportFixtureCheck*() =
  doAssert paramCount() == 6
  let text = readFile(paramStr(2))
  doAssert text.len <= 65536
  var wire = newSeq[byte](text.len)
  # Keep original report bytes stable through borrowed decoding and independent re-encoding.
  for i in 0..<text.len: wire[i] = byte(text[i])
  let parsed = decodeReportBorrowed(wire, 341)
  doAssert parsed.error == CompositeError.None and parsed.consumed == wire.len
  var output = newSeq[byte](wire.len)
  let encoded = encodeReportBorrowed(parsed.value, wire, 341, output)
  doAssert encoded.error == CompositeError.None and encoded.written == wire.len and output == wire
  let message = guaranteeMessage(wire)
  doAssert message.error == CryptoError.None
  let bytes = array[46, byte](message.value)
  var valid = true
  # Both ordinary fixture credentials must verify; invalid cases report false without timing anything.
  for i in 0..<2:
    let key = importPublicKey(reportUnhex(paramStr(3+2*i)))
    let signature = importSignature(reportUnhex(paramStr(4+2*i)))
    doAssert key.error == CryptoError.None and signature.error == CryptoError.None
    let verified = verify(key.value, signature.value, bytes)
    valid = valid and verified
  echo "VERIFY ", reportHex(output), " ", reportHex(bytes), " ", ord(valid)
