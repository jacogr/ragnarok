# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted fixture adapter: no production secrets
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

# exact widths enter the typed primitive APIs.
import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/rawthreads
import ./nimony_batch_support
import ../../src/bandersnatch/bandersnatch as bandersnatch_bandersnatch

# Decode public fixture hex
# dash represents an empty context/additional-data array.
proc bytes(text: string): seq[byte] =
  # Empty fixtures have no first byte to address.
  if text == "-": return @[]
  assert text.len mod 2 == 0
  result = @[]
  # Copy complete byte pairs, with no integer narrowing of a full encoded field.
  for i in countup(0, text.len-1, 2): result.add octet(text[i..i+1])
# Display exact completed bytes, with no output shortened to a round-trip-only commitment.
proc emit(raw: openArray[byte]) =
  var text = ""
  # Every public byte is rendered in canonical lowercase hexadecimal.
  for b in raw: text.add(toHex(int(b), 2).toLowerAscii())
  echo text
# Encode only a successfully selected owned fixed result.
proc output[T](value: BsResult[T]) =
  # Failed imports/equations carry no default proof/hash to print.
  if value.error != BsError.None:
    echo "error:", ord(value.error)
    return
  # Each nominal proof role exposes only its complete fixed representation.
  when T is BsSignature:
    emit(array[96, byte](value.value)) # Ordinary complete proof bundle.
  elif T is BsRingProof:
    emit(array[784, byte](value.value)) # Complete anonymous proof bundle.
  elif T is BsRingRoot:
    emit(array[144, byte](value.value)) # Every compressed root byte remains visible.
  else:
    emit(array[32, byte](value.value)) # Public encodings and verified hashes retain all fixed bytes.
# Prove retained-key scope, input-copy stability, checked defaults and alias invalidation under ARC.
proc ownership() =
  var empty = default(BsKey)
  assert publicKey(empty).error == BsError.InvalidOwner
  var key = default(BsKey)
  block:
    var scalar = default(array[32, byte])
    scalar[0] = 1
    let imported = importScalar(scalar)
    assert imported.error == BsError.None
    key = imported.value
    let before = publicKey(key)
    scalar[0] = 2
    assert array[32, byte](before.value) == array[32, byte](publicKey(key).value)
  let alias = key
  let sig = sign(alias, [], [])
  assert sig.error == BsError.None
  let pub = publicKey(alias)
  assert verify(pub.value, sig.value, [], []).error == BsError.None
  close(key)
  assert publicKey(alias).error == BsError.InvalidOwner
  assert sign(alias, [], []).error == BsError.InvalidOwner
  close(alias)
  var setup = default(BsSetup)
  block:
    let imported = newSetup(8)
    assert imported.error == BsError.None
    setup = imported.value
  let other = setup
  close(setup)
  var member = default(array[32, byte])
  assert commitRing(other, member).error == BsError.InvalidOwner
  close(other)
  # Exact range guards precede native domain arithmetic.
  for size in [-1, 0, 1024]: assert newSetup(size).error == BsError.InvalidLength
  var initial = default(BsResult[BsOutput])
  assert initial.error == BsError.Uninitialized
  echo "ok"
# Exercise Rust-backed signing concurrently without sharing retained scalar owners between workers.
proc worker(argument: pointer) {.nimcall.} =
  let id = cast[ptr int](argument)[] # Borrowed identity storage remains alive until this worker is joined.
  var scalar = default(array[32, byte])
  scalar[0] = byte(id+1)
  let key = importScalar(scalar)
  assert key.error == BsError.None
  defer: close(key.value)
  let pub = publicKey(key.value)
  # Fresh proof state is local to every call and worker.
  for round in 0..<32:
    let sig = sign(key.value, scalar, [])
    assert sig.error == BsError.None
    assert verify(pub.value, sig.value, scalar, []).error == BsError.None
# Join all OS workers before releasing their native/ARC lifetime state.
proc concurrent() {.raises.} =
  var threads {.noinit.}: array[4, RawThread]
  var identities = [0, 1, 2, 3]
  var started = 0
  try:
    # Fixed thread records and argument slots remain stationary until every worker has stopped.
    for i in 0..<4:
      create(threads[i], worker, addr identities[i])
      inc started
  finally:
    # Even partial thread creation must join the workers that already borrowed caller storage.
    for i in 0..<started: join(threads[i])
  echo "ok"
# Dispatch one trusted command
# every owner has a scoped release and every failed import has no value.
proc main() {.raises.} =
  let a = commandLineParams()
  assert a.len >= 1
  # Dedicated lifetime/concurrency probes need no payload arguments.
  if a[0] == "O":
    ownership()
    return
  # Same-process Rust adapter thread safety.
  if a[0] == "T":
    concurrent()
    return
  # A failed result must reject value selection before any default output is visible.
  if a[0] == "F":
    var failed = default(BsResult[BsOutput])
    echo array[32, byte](failed.value)[0] # Checked failed-result selection must trap.
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
    let setup = newSetup(integer(a[1]))
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
      output(signRing(setup.value, key.value, integer(a[3]), bytes(a[4]), bytes(a[5]), bytes(a[6])))
  # Unknown commands identify a trusted harness mistake.
  else:
    quit(1)
try:
  main()
except:
  # Trusted fixture I/O/thread setup failure must fail separately from a typed proof rejection.
  quit(2)
