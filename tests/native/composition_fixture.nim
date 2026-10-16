## Test-only literal chapter fixture transport shared by independent ownership/guard binaries.
import std/[assertions, strutils, syncio, parseutils, cmdline]

## Read sixteen externally authored hex lines; setup failures cannot count as result contract rejections.
proc compositionFixture(path: string): seq[seq[byte]] =
  var text = ""
  try:
    text = readFile(path)
  except:
    # Missing trusted setup is distinct from an intended success-precondition failure.
    quit 2
  result = @[]
  # Raw bytes come from independent Python equations rather than production encoders.
  for line in text.splitLines():
    if line.len == 0: continue # Ignore the fixture's final newline only.
    assert line.len mod 2 == 0
    var bytes = newSeq[byte](line.len div 2)
    # Decode complete literal octets without normalizing any protocol bytes.
    for i in 0..<bytes.len:
      let pair = line[2*i..2*i+1]
      var octet: byte = 0
      assert parseHex(pair, octet) == 2
      bytes[i] = octet
    result.add(bytes)
  assert result.len == 16
