## Trusted test adapter; command arguments contain public test fixtures only, never production secrets.
import std/[os, strutils]
import primitives

# Decode trusted fixture hex; a dash is the empty message.
proc bytes(text: string): seq[byte] =
  # Empty fixtures avoid indexing an absent byte pair.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0
  # Preserve every pair rather than converting through a machine integer.
  for i in countup(0, text.len - 1, 2): result.add byte(parseHexInt(text[i..i+1]))

# Print a fixed owned result as lowercase hex after checking its success branch.
proc output[T](value: CryptoResult[T]) =
  # Failed operations expose only a reason.
  if value.error != CryptoError.None:
    echo "error"
    return
  var text = ""
  # Distinct fixed arrays retain their full byte width.
  when T is EdSignature:
    let raw = array[64, byte](value.value)
  else:
    # Hashes and encoded public keys each own exactly 32 bytes.
    let raw = array[32, byte](value.value)
  # Hex formatting iterates completed bytes without changing their nominal API type.
  for b in raw: text.add toHex(b, 2).toLowerAscii
  echo text

# Exercise retained ownership, default failures and exact-width validation under ARC.
proc ownership() =
  var empty: EdSeed
  doAssert publicKey(empty).error == CryptoError.InvalidSeed
  var initial: CryptoResult[EdPublicKey]
  doAssert initial.error == CryptoError.Uninitialized
  # All nearby invalid widths must fail before creating a payload.
  for n in [0, 1, 31, 33, 63, 65]:
    doAssert importSeed(newSeq[byte](n)).error == CryptoError.InvalidLength
    doAssert importPublicKey(newSeq[byte](n)).error == CryptoError.InvalidLength
  # A retained seed stays alive after its import result leaves scope.
  var retained: EdSeed
  block:
    var input: array[32, byte]
    let loaded = importSeed(input)
    doAssert loaded.error == CryptoError.None
    retained = loaded.value
    let before = publicKey(retained)
    input[0] = 42
    doAssert array[32, byte](before.value) == array[32, byte](publicKey(retained).value)
  let alias = retained
  let sig = sign(alias, [])
  let key = publicKey(alias)
  doAssert verify(key.value, sig.value, [])
  clearSeed(retained)
  doAssert publicKey(alias).error == CryptoError.InvalidSeed
  doAssert sign(retained, []).error == CryptoError.InvalidSeed
  clearSeed(empty)
  doAssert importSignature(newSeq[byte](63)).error == CryptoError.InvalidLength
  doAssert importSignature(newSeq[byte](65)).error == CryptoError.InvalidLength
  echo "ok"

# Run independent owners and hash contexts within one native process and one worker thread.
proc worker(id: int) {.thread.} =
  var input: array[32, byte]
  input[0] = byte(id)
  let loaded = importSeed(input)
  doAssert loaded.error == CryptoError.None
  defer: clearSeed(loaded.value)
  let public = publicKey(loaded.value)
  let expectedBlake = blake2b256(input)
  let expectedKeccak = keccak256(input)
  # Repeat all primitives without sharing retained ARC seed handles between threads.
  for round in 0..<128:
    let sig = sign(loaded.value, input)
    doAssert verify(public.value, sig.value, input)
    doAssert array[32, byte](blake2b256(input).value) == array[32, byte](expectedBlake.value)
    doAssert array[32, byte](keccak256(input).value) == array[32, byte](expectedKeccak.value)

# Join every worker before allowing its stack/ARC state to go out of scope.
proc concurrent() =
  var threads: array[4, Thread[int]]
  # Each worker imports its own deterministic public test seed.
  for i in 0..<4: createThread(threads[i], worker, i)
  joinThreads(threads)
  echo "ok"

# Dispatch one bounded trusted request; public API errors produce no encoded default values.
proc main() =
  let args = commandLineParams()
  doAssert args.len >= 1
  # A failed result cannot expose its default value even in optimized builds.
  if args[0] == "F":
    var failed: CryptoResult[EdPublicKey]
    echo array[32, byte](failed.value)
    return
  # Ownership tests deliberately create and clear aliases without exposing seed bytes.
  if args[0] == "O": ownership(); return
  # Native threads exercise same-process backend state isolation.
  if args[0] == "T": concurrent(); return
  let input = bytes(args[1])
  case args[0]
  # Hashes own their fixed outputs and borrow input only for this call.
  of "B": output(blake2b256(input))
  of "K": output(keccak256(input))
  # Imported keys and signatures must each pass their own exact-width check.
  of "V":
    let key = importPublicKey(input)
    let signature = importSignature(bytes(args[2]))
    if key.error != CryptoError.None or signature.error != CryptoError.None:
      echo "error" # Failed import has no value to verify.
    else:
      echo int(verify(key.value, signature.value, bytes(args[3]))) # Completed encodings reach the verifier.
  # Public derivation and signing retain a private input copy only for this request.
  of "P", "S":
    let seed = importSeed(input)
    if seed.error != CryptoError.None:
      echo "error" # Invalid seed lengths cannot yield a default signing identity.
    else:
      defer: clearSeed(seed.value)
      if args[0] == "P": output(publicKey(seed.value)) # Public derivation adds no message/domain.
      else: output(sign(seed.value, bytes(args[2]))) # Sign the exact fixture message.
  # Unknown trusted test commands should fail loudly in the harness.
  else: quit(1)
main()
