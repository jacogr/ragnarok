## Trusted fixture adapter: no production secrets
# exact widths enter the typed primitive APIs.
import std/[os, strutils]
import bandersnatch

# Decode public fixture hex
# dash represents an empty context/additional-data array.
proc bytes(text: string): seq[byte] =
  # Empty fixtures have no first byte to address.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0
  # Copy complete byte pairs, with no integer narrowing of a full encoded field.
  for i in countup(0, text.len-1, 2): result.add byte(parseHexInt(text[i..i+1]))
# Encode only a successfully selected owned fixed result.
proc output[T](value: BsResult[T]) =
  # Failed imports/equations carry no default proof/hash to print.
  if value.error != BsError.None:
    echo "error:", ord(value.error)
    return
  when T is BsSignature:
    let raw = array[96, byte](value.value) # Ordinary historical proof bundle.
  elif T is BsRingProof:
    let raw = array[784, byte](value.value) # Complete anonymous proof bundle.
  elif T is BsRingRoot:
    let raw = array[144, byte](value.value) # Root retains every compressed commitment byte.
  else:
    let raw = array[32, byte](value.value) # Public keys and verified outputs each own 32 bytes.
  var text = ""
  # Hex printing operates only on completed public bytes.
  for b in raw: text.add toHex(b, 2).toLowerAscii
  echo text
# Prove retained-key scope, input-copy stability, checked defaults and alias invalidation under ARC.
proc ownership() =
  var empty: BsKey
  doAssert publicKey(empty).error == BsError.InvalidOwner
  var key: BsKey
  block:
    var scalar: array[32, byte]
    scalar[0] = 1
    let imported = importScalar(scalar)
    doAssert imported.error == BsError.None
    key = imported.value
    let before = publicKey(key)
    scalar[0] = 2
    doAssert array[32, byte](before.value) == array[32, byte](publicKey(key).value)
  let alias = key
  let sig = sign(alias, [], [])
  doAssert sig.error == BsError.None
  let pub = publicKey(alias)
  doAssert verify(pub.value, sig.value, [], []).error == BsError.None
  close(key)
  doAssert publicKey(alias).error == BsError.InvalidOwner
  doAssert sign(alias, [], []).error == BsError.InvalidOwner
  close(alias)
  var setup: BsSetup
  block:
    let imported = newSetup(8)
    doAssert imported.error == BsError.None
    setup = imported.value
  let other = setup
  close(setup)
  var member: array[32, byte]
  doAssert commitRing(other, member).error == BsError.InvalidOwner
  close(other)
  # Exact range guards precede native domain arithmetic.
  for size in [-1, 0, 1024]: doAssert newSetup(size).error == BsError.InvalidLength
  var initial: BsResult[BsOutput]
  doAssert initial.error == BsError.Uninitialized
  echo "ok"
# Exercise Rust-backed signing concurrently without sharing retained scalar owners between workers.
proc worker(id: int) {.thread.} =
  var scalar: array[32, byte]
  scalar[0] = byte(id+1)
  let key = importScalar(scalar)
  doAssert key.error == BsError.None
  defer: close(key.value)
  let pub = publicKey(key.value)
  # Fresh proof state is local to every call and worker.
  for round in 0..<32:
    let sig = sign(key.value, scalar, [])
    doAssert sig.error == BsError.None
    doAssert verify(pub.value, sig.value, scalar, []).error == BsError.None
# Join all OS workers before releasing their native/ARC lifetime state.
proc concurrent() =
  var threads: array[4, Thread[int]]
  # Each worker receives only a fixture identity, not another thread's secret handle.
  for i in 0..<4: createThread(threads[i], worker, i)
  joinThreads(threads)
  echo "ok"
# Dispatch one trusted command
# every owner has a scoped release and every failed import has no value.
proc main() =
  let a = commandLineParams()
  doAssert a.len >= 1
  # Dedicated lifetime/concurrency probes need no payload arguments.
  if a[0] == "O":
    ownership()
    return
  # Same-process Rust adapter thread safety.
  if a[0] == "T":
    concurrent()
    return
  if a[0] == "F":
    var failed: BsResult[BsOutput]
    echo array[32, byte](failed.value) # Checked failed-result selection must trap.
    return
  case a[0]
  # Derivation/signing start only after canonical private scalar import.
  of "P", "S":
    let key = importScalar(bytes(a[1]))
    # No default secret exists.
    if key.error != BsError.None:
      echo "error:", ord(key.error)
      return
    defer: close(key.value)
    # Derive an owned public encoding.
    if a[0] == "P":
      output(publicKey(key.value))
    # Preserve distinct raw context/additional data.
    else:
      output(sign(key.value, bytes(a[2]), bytes(a[3])))
  # Ordinary proof/key imports validate width before verification.
  of "V":
    let pub = importPublicKey(bytes(a[1]))
    let sig = importSignature(bytes(a[2]))
    # Invalid point cannot be used.
    if pub.error != BsError.None:
      echo "error:", ord(pub.error)
      return
    # No truncated/default proof enters verification.
    if sig.error != BsError.None:
      echo "error:", ord(sig.error)
      return
    output(verify(pub.value, sig.value, bytes(a[3]), bytes(a[4])))
  # Root commitment, proving and verification all select one explicit SRS/domain capacity.
  of "R", "G", "W":
    let setup = newSetup(parseInt(a[1]))
    # Wrong capacities create no owner.
    if setup.error != BsError.None:
      echo "error:", ord(setup.error)
      return
    defer: close(setup.value)
    # Ring normalization belongs to Nim.
    if a[0] == "R":
      output(commitRing(setup.value, bytes(a[2])))
    elif a[0] == "W":
      let root = importRingRoot(bytes(a[2]))
      let proof = importRingProof(bytes(a[3]))
      # Fixed commitment width first.
      if root.error != BsError.None:
        echo "error:", ord(root.error)
        return
      # Then fixed anonymous proof width.
      if proof.error != BsError.None:
        echo "error:", ord(proof.error)
        return
      output(verifyRing(setup.value, root.value, proof.value, bytes(a[4]), bytes(a[5])))
    else:
      let key = importScalar(bytes(a[2])) # Anonymous proving retains a private key only in this scope.
 # Failed scalar import cannot prove membership.
      if key.error != BsError.None:
        echo "error:", ord(key.error)
        return
      defer: close(key.value)
      output(signRing(setup.value, key.value, parseInt(a[3]), bytes(a[4]), bytes(a[5]), bytes(a[6])))
  # Unknown commands identify a trusted harness mistake.
  else:
    quit(1)
main()
