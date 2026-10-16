## Typed synchronous primitives for the GP 0.8.0 release-designated ark-vrf 0.2.2 Bandersnatch profile.
## Inputs are borrowed for one call. No implicit protocol domains or codec serialization.
const Header = "bridge.h"
# Import a canonical nonzero scalar into one opaque native owner.
proc keyNew(data: nil pointer, length: csize_t, output: ptr (
    nil pointer)): uint32 {.importc: "bs_key_new", header: Header, cdecl, raises: [], gcsafe.}
# Last-owner release cleanses the retained scalar in Rust.
proc keyFree(handle: nil pointer) {.importc: "bs_key_free", header: Header, cdecl, raises: [], gcsafe.}
# Copy public bytes from a live private scalar owner.
proc nativePublic(handle, output: nil pointer): uint32 {.importc: "bs_public", header: Header,
    cdecl, raises: [], gcsafe.}
# Produce a full 96-byte proof without retaining input or additional-data pointers.
proc nativeSign(handle, data: nil pointer, length: csize_t, ad: nil pointer, adLen: csize_t,
    output: nil pointer): uint32 {.importc: "bs_sign", header: Header, cdecl, raises: [], gcsafe.}
# Verified output bytes are committed only after public key/context/proof verification succeeds.
proc nativeVerify(key, signature: nil pointer, signatureLen: csize_t, data: nil pointer,
    length: csize_t, ad: nil pointer, adLen: csize_t,
        output: nil pointer): uint32 {.importc: "bs_verify", header: Header,
    cdecl, raises: [], gcsafe.}
# Create immutable trusted-SRS parameters for a bounded ring capacity.
proc setupNew(size: csize_t, output: ptr (nil pointer)): uint32 {.importc: "bs_setup_new",
    header: Header, cdecl, raises: [], gcsafe.}
# Destroy one native parameter owner; aliases must stop using released storage.
proc setupFree(handle: nil pointer) {.importc: "bs_setup_free", header: Header, cdecl, raises: [], gcsafe.}
# Commit complete ordered canonical points into one 144-byte root.
proc nativeCommit(handle, keys: nil pointer, length: csize_t,
    output: nil pointer): uint32 {.importc: "bs_commit", header: Header, cdecl, raises: [], gcsafe.}
# Prove membership only for the actual in-range matching signing key.
proc nativeRingSign(handle, key: nil pointer, index: csize_t, keys: nil pointer, keysLen: csize_t,
    data: nil pointer, length: csize_t, ad: nil pointer, adLen: csize_t,
    output: nil pointer): uint32 {.importc: "bs_ring_sign", header: Header, cdecl, raises: [], gcsafe.}
# Verify root-bound proof with the selected ring domain and expose only a verified hash.
proc nativeRingVerify(handle, root, signature: nil pointer, signatureLen: csize_t,
    data: nil pointer, length: csize_t, ad: nil pointer, adLen: csize_t,
    output: nil pointer): uint32 {.importc: "bs_ring_verify", header: Header, cdecl, raises: [], gcsafe.}
# Validate canonical prime-subgroup encoding before copying a typed public key.
proc nativeValidate(data: nil pointer, length: csize_t): uint32 {.importc: "bs_validate_public",
    header: Header, cdecl, raises: [], gcsafe.}
# Export the pinned padding point for explicit native-language invalid-member substitution.
proc nativePadding(output: nil pointer): uint32 {.importc: "bs_padding", header: Header, cdecl,
    raises: [], gcsafe.}

type
  # Encoded public key, distinct from output hashes and other primitive keys.
  BsPublicKey* = distinct array[32, byte]
  # Owned complete output||c||s signature; not a newer Tiny/Thin VRF proof.
  BsSignature* = distinct array[96, byte]
  # Owned complete output/Pedersen/membership proof bundle.
  BsRingProof* = distinct array[784, byte]
  # Owned compressed ring commitment, bound to its setup domain and SRS.
  BsRingRoot* = distinct array[144, byte]
  # Only a successful verification operation exposes this nominal 32-byte VRF output hash.
  BsOutput* = distinct array[32, byte]
  # Typed ABI failures preserve default/owner/encoding/verification/backend distinctions.
  BsError* {.pure.} = enum
    Uninitialized, None, InvalidLength, InvalidEncoding, InvalidOwner, VerificationFailure,
      BackendFailure, BackendPanic
  # Checked result carries a value only in the successful branch.
  BsResult*[T] = object
    case status: BsError
    of None:
      # Completed owned bytes/handles exist only here.
      completed: T
    else:
      # Failures have no default scalar, proof or verified output.
      discard
  # Private allocation category selects the matching Rust destructor.
  NativeKind = enum SecretKind, SetupKind
  # Acyclic ARC storage shares ownership without exposing the native pointer/layout.
  NativeState = object
    handle: nil pointer
    kind: NativeKind
  # Private acyclic ARC reference; explicit nil storage represents a default owner.
  NativeData = ref NativeState
  # Opaque scalar owner; aliases retain ARC storage and closing one invalidates all aliases.
  BsKey* = object
    state: nil NativeData
  # Opaque immutable ring parameter owner; its domain/SRS must match each root/proof.
  BsSetup* = object
    state: nil NativeData

# Read only the outcome; failed/default operations carry no native handle or proof value.
func error*[T](value: BsResult[T]): BsError = value.status

# Success contracts protect every fixed value, normalized sequence and opaque native owner.
func value*[T](value: BsResult[T]): T {.inline, requires: value.status == BsError.None.} =
  value.completed

# Release native allocations exactly once, including when the last retained ARC reference leaves scope.
proc `=destroy`(state: NativeState) {.raises: [], gcsafe.} =
  # Explicit close already releases its native allocation.
  if state.handle == nil: return
  case state.kind
  # Secret destruction zeroizes the Rust scalar.
  of SecretKind: keyFree(state.handle)
  # Public parameter allocations are released through their original Rust allocator.
  of SetupKind: setupFree(state.handle)

# Normalize immutable ABI reason codes without manufacturing success for unknown outcomes.
proc error(code: uint32): BsError {.raises: [], gcsafe.} =
  case code
  of 0: BsError.None # Only native success publishes output.
  of 1: BsError.InvalidLength # Width/capacity/resource checks failed.
  of 2: BsError.InvalidEncoding # Canonical/subgroup/identity profile validation failed.
  of 3: BsError.InvalidOwner # Missing/default/closed handle.
  of 4: BsError.VerificationFailure # A decoded proof did not verify.
  of 6: BsError.BackendPanic # An unwind was contained inside Rust.
  else: BsError.BackendFailure # Includes unexpected ABI status codes.

# Borrow an input address synchronously; empty slices intentionally have no element pointer.
proc data(input: openArray[byte]): nil pointer {.raises: [], gcsafe.} =
  # Do not evaluate element zero for an empty context/additional-data buffer.
  if input.len == 0: return nil
  unsafeAddr input[0]

# Select a live opaque key pointer without exposing it to callers.
proc handle(key: BsKey): nil pointer {.raises: [], gcsafe.} =
  # Default retained keys fail before any native dereference.
  let state = key.state
  if state == nil: return nil # A default key has no native allocation.
  state.handle
# Select a live immutable ring parameter allocation; callers cannot forge native layouts.
proc handle(setup: BsSetup): nil pointer {.raises: [], gcsafe.} =
  # Default setups have no trusted SRS/domain.
  let state = setup.state
  if state == nil: return nil # A default setup has no native allocation.
  state.handle

# Import exactly one canonical nonzero scalar, not a seed; caller retains responsibility for original secret bytes.
proc importScalar*(input: openArray[byte]): BsResult[BsKey] {.raises: [], gcsafe.} =
  var native: nil pointer = nil
  let reason = error(keyNew(data(input), csize_t(input.len), addr native))
  # Native import errors contain no pointer or default key value.
  if reason != BsError.None: return BsResult[BsKey](status: reason)
  let state = NativeData(handle: native, kind: SecretKind)
  BsResult[BsKey](status: BsError.None, completed: BsKey(state: state))

# Build immutable trusted-SRS parameters; capacity is bounded before conversion to native size_t.
proc newSetup*(capacity: int): BsResult[BsSetup] {.raises: [], gcsafe.} =
  # Negative, empty and unsupported capacities cannot wrap or change the SRS domain implicitly.
  if capacity < 1 or capacity > 1023: return BsResult[BsSetup](status: BsError.InvalidLength)
  var native: nil pointer = nil
  let reason = error(setupNew(csize_t(capacity), addr native))
  # Failed initialization leaves no usable setup metadata.
  if reason != BsError.None: return BsResult[BsSetup](status: reason)
  let state = NativeData(handle: native, kind: SetupKind)
  BsResult[BsSetup](status: BsError.None, completed: BsSetup(state: state))

# Close a retained key once; shared ARC aliases observe the cleared native pointer and fail subsequent operations.
proc close*(key: BsKey) {.raises: [], gcsafe.} =
  # Default/already closed keys contain no allocation to release.
  let state = key.state
  if state == nil or state.handle == nil: return # Defaults and already closed aliases have nothing to release.
  keyFree(state.handle)
  state.handle = nil
# Close retained setup allocation; no alias may race close with an in-flight operation.
proc close*(setup: BsSetup) {.raises: [], gcsafe.} =
  # Clearing an absent/already closed retained owner is harmless.
  let state = setup.state
  if state == nil or state.handle == nil: return # Release each shared native setup only once.
  setupFree(state.handle)
  state.handle = nil

# Validate exact canonical public encodings, then retain a fixed independent copy.
proc importPublicKey*(input: openArray[byte]): BsResult[BsPublicKey] {.raises: [], gcsafe.} =
  let reason = error(nativeValidate(data(input), csize_t(input.len)))
  if reason != BsError.None: return BsResult[BsPublicKey](status: reason)
  var output = default(array[32, byte])
  # Own bytes rather than retaining the caller's mutable storage.
  for i in 0..<32: output[i] = input[i]
  BsResult[BsPublicKey](status: BsError.None, completed: BsPublicKey(output))

# Copy a bounded member sequence with the existing explicit invalid-encoding padding policy.
proc normalizeRing*(input: openArray[byte]): BsResult[seq[byte]] {.raises: [], gcsafe.} =
  # Complete encoded members and a bounded count are required before allocating/copying.
  if input.len == 0 or input.len mod 32 != 0 or input.len > 1023*32:
    return BsResult[seq[byte]](status: BsError.InvalidLength)
  var padding = default(array[32, byte])
  let reason = error(nativePadding(addr padding[0]))
  # Backend configuration failures must not silently substitute zero bytes.
  if reason != BsError.None: return BsResult[seq[byte]](status: reason)
  var output = newSeq[byte](input.len)
  for index in countup(0, input.len-32, 32):
    let status = error(nativeValidate(unsafeAddr input[index], 32))
    if status != BsError.None and status != BsError.InvalidEncoding:
      return BsResult[seq[byte]](status: status)
    let valid = status == BsError.None
    for i in 0..<32:
      # Invalid-member substitution is explicit language policy; valid identity remains unchanged and later fails the adapter guard.
      if valid: output[index+i] = input[index+i]
      else: output[index+i] = padding[i]
  BsResult[seq[byte]](status: BsError.None, completed: output)

# Derive one owned canonical public key from a live opaque scalar.
proc publicKey*(key: BsKey): BsResult[BsPublicKey] {.raises: [], gcsafe.} =
  var output = default(array[32, byte])
  let reason = error(nativePublic(handle(key), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsPublicKey](status: reason)
  BsResult[BsPublicKey](status: BsError.None, completed: BsPublicKey(output))

# Sign exact raw context and additional bytes separately; output owns the full historical 96-byte signature.
proc sign*(key: BsKey, context, additional: openArray[byte]): BsResult[BsSignature] {.raises: [], gcsafe.} =
  var output = default(array[96, byte])
  let reason = error(nativeSign(handle(key), data(context), csize_t(context.len), data(additional),
      csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsSignature](status: reason)
  BsResult[BsSignature](status: BsError.None, completed: BsSignature(output))

# Verify a complete typed proof; only success carries the extracted 32-byte output hash.
proc verify*(key: BsPublicKey, signature: BsSignature, context, additional: openArray[
    byte]): BsResult[BsOutput] {.raises: [], gcsafe.} =
  var public = array[32, byte](key)
  var proof = array[96, byte](signature)
  var output = default(array[32, byte])
  let reason = error(nativeVerify(addr public[0], addr proof[0], 96, data(context), csize_t(
      context.len), data(additional), csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsOutput](status: reason)
  BsResult[BsOutput](status: BsError.None, completed: BsOutput(output))

# Commit the complete normalized ordered membership under a live setup.
proc commitRing*(setup: BsSetup, members: openArray[byte]): BsResult[BsRingRoot] {.raises: [], gcsafe.} =
  let normalized = normalizeRing(members)
  # Ring syntax/setup policy must succeed before selecting member bytes.
  if normalized.error != BsError.None: return BsResult[BsRingRoot](status: normalized.error)
  var output = default(array[144, byte])
  let reason = error(nativeCommit(handle(setup), data(normalized.value), csize_t(
      normalized.value.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsRingRoot](status: reason)
  BsResult[BsRingRoot](status: BsError.None, completed: BsRingRoot(output))

# Prove membership only for a valid matching index and live secret; Rust borrows all buffers synchronously.
proc signRing*(setup: BsSetup, key: BsKey, index: int, members, context, additional: openArray[
    byte]): BsResult[BsRingProof] {.raises: [], gcsafe.} =
  let normalized = normalizeRing(members)
  # Ring syntax/setup policy must succeed before selecting member bytes.
  if normalized.error != BsError.None: return BsResult[BsRingProof](status: normalized.error)
  # A negative index cannot wrap into an unsigned native position.
  if index < 0: return BsResult[BsRingProof](status: BsError.InvalidLength)
  var output = default(array[784, byte])
  let reason = error(nativeRingSign(handle(setup), handle(key), csize_t(index), data(
      normalized.value), csize_t(normalized.value.len), data(context), csize_t(context.len), data(
      additional), csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsRingProof](status: reason)
  BsResult[BsRingProof](status: BsError.None, completed: BsRingProof(output))

# Verify root-bound ring proof using explicit domain/SRS parameters; failed proofs expose no output hash.
proc verifyRing*(setup: BsSetup, root: BsRingRoot, signature: BsRingProof, context,
    additional: openArray[byte]): BsResult[BsOutput] {.raises: [], gcsafe.} =
  var commitment = array[144, byte](root)
  var proof = array[784, byte](signature)
  var output = default(array[32, byte])
  let reason = error(nativeRingVerify(handle(setup), addr commitment[0], addr proof[0], 784, data(
      context), csize_t(context.len), data(additional), csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsOutput](status: reason)
  BsResult[BsOutput](status: BsError.None, completed: BsOutput(output))

# Import exact ordinary proof width as fixed bytes; verification establishes validity separately.
proc importSignature*(input: openArray[byte]): BsResult[BsSignature] {.raises: [], gcsafe.} =
  # Wrong widths fail before constructing a typed default or truncating trailing bytes.
  if input.len != 96: return BsResult[BsSignature](status: BsError.InvalidLength)
  var output = default(array[96, byte])
  # Copy all public bytes into independent owned storage.
  for i in 0..<96: output[i] = input[i]
  BsResult[BsSignature](status: BsError.None, completed: BsSignature(output))

# Import the complete fixed ring-proof bundle without truncation or implied verification.
proc importRingProof*(input: openArray[byte]): BsResult[BsRingProof] {.raises: [], gcsafe.} =
  # Wrong widths fail before constructing a typed default or truncating trailing bytes.
  if input.len != 784: return BsResult[BsRingProof](status: BsError.InvalidLength)
  var output = default(array[784, byte])
  # Copy all public bytes into independent owned storage.
  for i in 0..<784: output[i] = input[i]
  BsResult[BsRingProof](status: BsError.None, completed: BsRingProof(output))

# Import one fixed commitment encoding; setup/root validity remains a verification responsibility.
proc importRingRoot*(input: openArray[byte]): BsResult[BsRingRoot] {.raises: [], gcsafe.} =
  # Wrong widths fail before constructing a typed default or truncating trailing bytes.
  if input.len != 144: return BsResult[BsRingRoot](status: BsError.InvalidLength)
  var output = default(array[144, byte])
  # Copy all public bytes into independent owned storage.
  for i in 0..<144: output[i] = input[i]
  BsResult[BsRingRoot](status: BsError.None, completed: BsRingRoot(output))
