## Trusted batch transport for the independent identity/framing oracle; all validation remains production Nim.
import std/[assertions, cmdline, strutils, syncio]
import ./batch_support
import ../../src/quic/protocol

# Empty tokens use dash; bounded fixture hex never invokes a permissive integer parser.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty DER/header/frame remains explicit.
  assert text.len mod 2 == 0 and text.len <= 40000
  result = newSeq[byte](text.len div 2)
  # Copy every complete trusted byte; production functions receive exact original inputs.
  for i in 0..<result.len: result[i] = octet(text[2*i..2*i+1])

# Dispatch independent requests without substituting a Python verifier or native transport engine.
proc request(parts: seq[string]) =
  case parts[0]
  of "N":
    # Exact 32-byte names preserve all 54 SAN bytes, including their leading dollar sign.
    let raw = unhex(parts[1])
    assert raw.len == 32
    var key = default(array[32, byte])
    for i in 0..<32: key[i] = raw[i] # Copy into the fixed identity input.
    var text = ""
    for b in peerName(key): text.add(char(b)) # Render complete public ASCII identity bytes.
    echo text
  of "D":
    # Certificate bytes are borrowed only for the synchronous C extractor and native identity policy.
    var raw = unhex(parts[2])
    var data: nil ptr byte = nil
    if raw.len > 0: data = addr raw[0] # Empty DER has no first byte.
    echo ord(validPeer(data, csize_t(raw.len), unhex(parts[1])))
  of "L":
    # Length failures print only their reason, never a fabricated successful zero.
    let checked = checkedLength(unhex(parts[2]), integer(parts[1]))
    if checked.error == FrameError.None: echo "ok ", checked.value
    else: echo ord(checked.error) # No unsuccessful value selection is allowed.
  of "F":
    # Frame success requires the exact original caller-provided FIN and size policy.
    let checked = inspectFrame(unhex(parts[4]), integer(parts[1]) == 1,
        integer(parts[3]), integer(parts[2]) == 1)
    if checked.error == FrameError.None: echo "ok ", checked.size, " ", checked.extent
    else: echo ord(checked.error) # Pending/failed frames contain no payload metadata.
  else:
    # Unknown operations indicate a trusted harness error rather than a protocol rejection.
    quit(2)

# Fixture file I/O is separate from parser errors; every line produces exactly one complete response.
proc main() {.raises.} =
  let args = commandLineParams()
  assert args.len == 1
  for line in lines(args[0]): request(line.splitWhitespace()) # Every corpus request is explicit.

# Trusted file errors must not be mistaken for a successful parser verdict.
try:
  main()
except:
  quit(2)
