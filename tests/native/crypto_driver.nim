## Trusted test adapter; command arguments contain public test fixtures only, never production secrets.
import std/[assertions, cmdline, strutils, syncio, parseutils, rawthreads]
import ../../src/crypto/primitives

# Decode trusted fixture hex; a dash is the empty message.
proc bytes(text: string): seq[byte] {.raises.} =
  # Empty fixtures have no octet to inspect.
  if text == "-": return @[]
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Each validated byte belongs to this independently mutable public fixture buffer.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    for c in pair: assert c in {'0'..'9', 'a'..'f'} # Trusted transport accepts exact lowercase hex only.
    var value: byte = 0
    assert parseHex(pair, value) == 2
    result[i] = value

# Print a fixed owned result as lowercase hex after checking its success branch.
proc hex(bytes: openArray[byte]): string =
  result = ""
  # Every fixed output octet remains visible, including leading zeroes.
  for value in bytes: result.add(toHex(int(value), 2).toLowerAscii())

# Each public fixed result retains its nominal role until successful selection.
proc output(value: CryptoResult[Blake2bHash]) =
  if value.error != CryptoError.None: echo "error" # No digest exists after backend failure.
  else: echo hex(array[32, byte](value.value)) # Hash output owns exactly 32 bytes.
# Legacy Keccak output cannot be substituted for a Blake2b result.
proc output(value: CryptoResult[KeccakHash]) =
  if value.error != CryptoError.None: echo "error" # Failed hashes have no output bytes.
  else: echo hex(array[32, byte](value.value)) # Preserve the complete legacy digest.
# Public derivation/import publishes fixed copied key bytes only on success.
proc output(value: CryptoResult[EdPublicKey]) =
  if value.error != CryptoError.None: echo "error" # Failed keys are not zero identities.
  else: echo hex(array[32, byte](value.value)) # No borrowed backend pointer escapes.
# Ordinary signatures retain all 64 bytes and require successful signing/import.
proc output(value: CryptoResult[EdSignature]) =
  if value.error != CryptoError.None: echo "error" # No signature is published after failure.
  else: echo hex(array[64, byte](value.value)) # Never pad or truncate a signature.

# Exercise retained ownership, default failures and exact-width validation under ARC.
proc ownership() =
  var empty: EdSeed = default(EdSeed)
  assert publicKey(empty).error == CryptoError.InvalidSeed
  var initial: CryptoResult[EdPublicKey] = default(CryptoResult[EdPublicKey])
  assert initial.error == CryptoError.Uninitialized
  # All nearby invalid widths must fail before creating a payload.
  for n in [0, 1, 31, 33, 63, 65]:
    assert importSeed(newSeq[byte](n)).error == CryptoError.InvalidLength
    assert importPublicKey(newSeq[byte](n)).error == CryptoError.InvalidLength
  # A retained seed stays alive after its import result leaves scope.
  var retained: EdSeed = default(EdSeed)
  block:
    var input: array[32, byte] = default(array[32, byte])
    let loaded = importSeed(input)
    assert loaded.error == CryptoError.None
    retained = loaded.value
    let before = publicKey(retained)
    input[0] = 42
    assert array[32, byte](before.value) == array[32, byte](publicKey(retained).value)
  let alias = retained
  let sig = sign(alias, [])
  let key = publicKey(alias)
  assert verify(key.value, sig.value, [])
  clearSeed(retained)
  assert publicKey(alias).error == CryptoError.InvalidSeed
  assert sign(retained, []).error == CryptoError.InvalidSeed
  clearSeed(empty)
  assert importSignature(newSeq[byte](63)).error == CryptoError.InvalidLength
  assert importSignature(newSeq[byte](65)).error == CryptoError.InvalidLength
  echo "ok"

# Run independent owners and hash contexts within one native process and one worker thread.
proc worker(argument: pointer) =
  let id = cast[ptr int](argument)[]
  var input: array[32, byte] = default(array[32, byte])
  input[0] = byte(id)
  let loaded = importSeed(input)
  assert loaded.error == CryptoError.None
  defer: clearSeed(loaded.value)
  let public = publicKey(loaded.value)
  let expectedBlake = blake2b256(input)
  let expectedKeccak = keccak256(input)
  # Repeat all primitives without sharing retained ARC seed handles between threads.
  for round in 0..<128:
    let sig = sign(loaded.value, input)
    assert verify(public.value, sig.value, input)
    assert array[32, byte](blake2b256(input).value) == array[32, byte](expectedBlake.value)
    assert array[32, byte](keccak256(input).value) == array[32, byte](expectedKeccak.value)

# Join every worker before allowing its stack/ARC state to go out of scope.
proc concurrent() {.raises.} =
  var threads: array[4, RawThread] = default(array[4, RawThread])
  var ids = [0, 1, 2, 3]
  var started = 0
  try:
    # Each worker imports its own public fixture seed; no ARC seed owner crosses a thread boundary.
    for i in 0..<4:
      create(threads[i], worker, addr ids[i])
      inc started
  finally:
    # Also join already-started workers if a later thread creation fails.
    for i in 0..<started: join(threads[i])
  echo "ok"

# Dispatch one bounded trusted request; public API errors produce no encoded default values.
proc main() {.raises.} =
  let args = commandLineParams()
  assert args.len >= 1
  # A failed result cannot expose its default value even in optimized builds.
  if args[0] == "F":
    var failed: CryptoResult[EdPublicKey] = default(CryptoResult[EdPublicKey])
    echo hex(array[32, byte](failed.value))
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
try:
  main()
except:
  # Trusted fixture parsing or thread creation errors fail independently of typed crypto rejection.
  quit(2)
