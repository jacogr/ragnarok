## Typed synchronous primitives for the pinned historical JAM Bandersnatch research profile.
## Inputs are borrowed for one call. No implicit protocol domains or codec serialization.
const Header = "../../native/bandersnatch/bridge.h"
# Import a canonical nonzero scalar into one opaque native owner.
proc keyNew(data: pointer, length: csize_t, output: ptr pointer): uint32 {.importc: "bs_key_new",
    header: Header, cdecl, raises: [], gcsafe.}
# Last-owner release cleanses the retained scalar in Rust.
proc keyFree(handle: pointer) {.importc: "bs_key_free", header: Header, cdecl, raises: [], gcsafe.}
# Copy the owner's public encoding into exactly 32 caller bytes.
proc nativePublic(handle, output: pointer): uint32 {.importc: "bs_public", header: Header, cdecl,
    raises: [], gcsafe.}
# Produce a full 96-byte proof without retaining input or additional-data pointers.
proc nativeSign(handle, data: pointer, length: csize_t, ad: pointer, adLen: csize_t,
    output: pointer): uint32 {.importc: "bs_sign", header: Header, cdecl, raises: [], gcsafe.}
# Verified output bytes are committed only after public key/context/proof verification succeeds.
proc nativeVerify(key, signature: pointer, signatureLen: csize_t, data: pointer, length: csize_t,
    ad: pointer, adLen: csize_t, output: pointer): uint32 {.importc: "bs_verify", header: Header,
    cdecl, raises: [], gcsafe.}
# Create immutable trusted-SRS parameters for a bounded ring capacity.
proc setupNew(size: csize_t, output: ptr pointer): uint32 {.importc: "bs_setup_new", header: Header,
    cdecl, raises: [], gcsafe.}
# Destroy one native parameter owner; aliases must stop using released storage.
proc setupFree(handle: pointer) {.importc: "bs_setup_free", header: Header, cdecl, raises: [], gcsafe.}
# Commit complete ordered canonical points into one 144-byte root.
proc nativeCommit(handle, keys: pointer, length: csize_t,
    output: pointer): uint32 {.importc: "bs_commit", header: Header, cdecl, raises: [], gcsafe.}
# Prove membership only for the actual in-range matching signing key.
proc nativeRingSign(handle, key: pointer, index: csize_t, keys: pointer, keysLen: csize_t,
    data: pointer, length: csize_t, ad: pointer, adLen: csize_t,
    output: pointer): uint32 {.importc: "bs_ring_sign", header: Header, cdecl, raises: [], gcsafe.}
# Verify root-bound proof with the selected ring domain and expose only a verified hash.
proc nativeRingVerify(handle, root, signature: pointer, signatureLen: csize_t, data: pointer,
    length: csize_t, ad: pointer, adLen: csize_t,
    output: pointer): uint32 {.importc: "bs_ring_verify", header: Header, cdecl, raises: [], gcsafe.}
# Validate canonical prime-subgroup encoding before ring normalization.
proc nativeValidate(data: pointer, length: csize_t): uint32 {.importc: "bs_validate_public",
    header: Header, cdecl, raises: [], gcsafe.}
# Export the pinned padding point for explicit native-language invalid-member substitution.
proc nativePadding(output: pointer): uint32 {.importc: "bs_padding", header: Header, cdecl,
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
  # Defaults fail and malformed encodings, failed equations and caught backend panics remain separate.
  BsError* {.pure.} = enum
    Uninitialized, None, InvalidLength, InvalidEncoding, InvalidOwner, VerificationFailure,
      BackendFailure, BackendPanic
  # Checked result carries a value only in the successful branch.
  BsResult*[T] = object
    case error*: BsError
    of BsError.None:
      # Completed owned bytes/handles exist only here.
      value*: T
    else:
      # Failures have no default scalar, proof or verified output.
      discard
  # Private allocation category selects the matching Rust destructor.
  NativeKind = enum SecretKind, SetupKind
  # Acyclic ARC storage shares ownership without exposing the native pointer/layout.
  NativeState = object
    handle: pointer
    kind: NativeKind
  # Opaque scalar owner; aliases retain ARC storage and closing one invalidates all aliases.
  BsKey* = object
    state: ref NativeState
  # Opaque immutable ring parameter owner; its domain/SRS must match each root/proof.
  BsSetup* = object
    state: ref NativeState

# Release native allocations exactly once, including when the last retained ARC reference leaves scope.
proc `=destroy`(state: var NativeState) {.raises: [], gcsafe.} =
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
proc data(input: openArray[byte]): pointer {.raises: [], gcsafe.} =
  # Do not evaluate element zero for an empty context/additional-data buffer.
  if input.len == 0: return nil
  unsafeAddr input[0]

# Select a live opaque key pointer without exposing it to callers.
proc handle(key: BsKey): pointer {.raises: [], gcsafe.} =
  # Default retained keys fail before any native dereference.
  if key.state.isNil: return nil
  key.state.handle
# Select a live immutable ring parameter allocation; callers cannot forge native layouts.
proc handle(setup: BsSetup): pointer {.raises: [], gcsafe.} =
  # Default setups have no trusted SRS/domain.
  if setup.state.isNil: return nil
  setup.state.handle

# Import exactly one canonical nonzero scalar, not a seed; caller retains responsibility for original secret bytes.
proc importScalar*(input: openArray[byte]): BsResult[BsKey] {.raises: [], gcsafe.} =
  var native: pointer
  let reason = error(keyNew(data(input), csize_t(input.len), addr native))
  # Native import errors contain no pointer or default key value.
  if reason != BsError.None: return BsResult[BsKey](error: reason)
  var state: ref NativeState
  new(state)
  state.handle = native
  state.kind = SecretKind
  BsResult[BsKey](error: BsError.None, value: BsKey(state: state))

# Build immutable trusted-SRS parameters; capacity is bounded before conversion to native size_t.
proc newSetup*(capacity: int): BsResult[BsSetup] {.raises: [], gcsafe.} =
  # Negative, empty and unsupported capacities cannot wrap or change the SRS domain implicitly.
  if capacity < 1 or capacity > 1023: return BsResult[BsSetup](error: BsError.InvalidLength)
  var native: pointer
  let reason = error(setupNew(csize_t(capacity), addr native))
  # Failed initialization leaves no usable setup metadata.
  if reason != BsError.None: return BsResult[BsSetup](error: reason)
  var state: ref NativeState
  new(state)
  state.handle = native
  state.kind = SetupKind
  BsResult[BsSetup](error: BsError.None, value: BsSetup(state: state))

# Close a retained key once; shared ARC aliases observe the cleared native pointer and fail subsequent operations.
proc close*(key: BsKey) {.raises: [], gcsafe.} =
  # Default/already closed keys contain no allocation to release.
  if key.state.isNil or key.state.handle == nil: return
  keyFree(key.state.handle)
  key.state.handle = nil
# Close retained setup allocation; no alias may race close with an in-flight operation.
proc close*(setup: BsSetup) {.raises: [], gcsafe.} =
  # Clearing an absent/already closed retained owner is harmless.
  if setup.state.isNil or setup.state.handle == nil: return
  setupFree(setup.state.handle)
  setup.state.handle = nil

# Import complete public encoding with canonical/subgroup validation; verification applies identity guards separately.
proc importPublicKey*(input: openArray[byte]): BsResult[BsPublicKey] {.raises: [], gcsafe.} =
  let reason = error(nativeValidate(data(input), csize_t(input.len)))
  # A bad encoding/width cannot yield a usable key.
  if reason != BsError.None: return BsResult[BsPublicKey](error: reason)
  var output: array[32, byte]
  # Own bytes rather than retaining the caller's mutable storage.
  for i in 0..<32: output[i] = input[i]
  BsResult[BsPublicKey](error: BsError.None, value: BsPublicKey(output))

# Normalize an ordered borrowed ring in Nim; only invalid encodings become the specified padding point.
proc normalizeRing*(input: openArray[byte]): BsResult[seq[byte]] {.raises: [], gcsafe.} =
  # Complete encoded members and a bounded count are required before allocating/copying.
  if input.len == 0 or input.len mod 32 != 0 or input.len > 1023*32:
    return BsResult[seq[byte]](error: BsError.InvalidLength)
  var padding: array[32, byte]
  let reason = error(nativePadding(addr padding[0]))
  # Backend configuration failures must not silently substitute zero bytes.
  if reason != BsError.None: return BsResult[seq[byte]](error: reason)
  var output = newSeq[byte](input.len)
  # Preserve valid points in order, substituting only encodings without a canonical subgroup point.
  for index in countup(0, input.len-32, 32):
    let status = error(nativeValidate(unsafeAddr input[index], 32))
    # Only invalid encodings are substituted; a backend failure/panic must remain visible.
    if status != BsError.None and status != BsError.InvalidEncoding:
      return BsResult[seq[byte]](error: status)
    let valid = status == BsError.None
    for i in 0..<32:
      # Invalid-member substitution is explicit language policy; valid identity remains unchanged and later fails the adapter guard.
      if valid: output[index+i] = input[index+i]
      else: output[index+i] = padding[i]
  BsResult[seq[byte]](error: BsError.None, value: output)

# Derive one owned canonical public key from a live opaque scalar.
proc publicKey*(key: BsKey): BsResult[BsPublicKey] {.raises: [], gcsafe.} =
  var output: array[32, byte]
  let reason = error(nativePublic(handle(key), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsPublicKey](error: reason)
  BsResult[BsPublicKey](error: BsError.None, value: BsPublicKey(output))

# Sign exact raw context and additional bytes separately; output owns the full historical 96-byte signature.
proc sign*(key: BsKey, context, additional: openArray[byte]): BsResult[BsSignature] {.raises: [], gcsafe.} =
  var output: array[96, byte]
  let reason = error(nativeSign(handle(key), data(context), csize_t(context.len), data(additional),
      csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsSignature](error: reason)
  BsResult[BsSignature](error: BsError.None, value: BsSignature(output))

# Verify a complete typed proof; only success carries the extracted 32-byte output hash.
proc verify*(key: BsPublicKey, signature: BsSignature, context, additional: openArray[
    byte]): BsResult[BsOutput] {.raises: [], gcsafe.} =
  var public = array[32, byte](key)
  var proof = array[96, byte](signature)
  var output: array[32, byte]
  let reason = error(nativeVerify(addr public[0], addr proof[0], 96, data(context), csize_t(
      context.len), data(additional), csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsOutput](error: reason)
  BsResult[BsOutput](error: BsError.None, value: BsOutput(output))

# Normalize ordered invalid member encodings natively, then commit with the explicit SRS/domain owner.
proc commitRing*(setup: BsSetup, members: openArray[byte]): BsResult[BsRingRoot] {.raises: [], gcsafe.} =
  let normalized = normalizeRing(members)
  # Ring syntax/setup policy must succeed before selecting member bytes.
  if normalized.error != BsError.None: return BsResult[BsRingRoot](error: normalized.error)
  var output: array[144, byte]
  let reason = error(nativeCommit(handle(setup), data(normalized.value), csize_t(
      normalized.value.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsRingRoot](error: reason)
  BsResult[BsRingRoot](error: BsError.None, value: BsRingRoot(output))

# Prove membership only for a valid matching index and live secret; Rust borrows all buffers synchronously.
proc signRing*(setup: BsSetup, key: BsKey, index: int, members, context, additional: openArray[
    byte]): BsResult[BsRingProof] {.raises: [], gcsafe.} =
  let normalized = normalizeRing(members)
  # Ring syntax/setup policy must succeed before selecting member bytes.
  if normalized.error != BsError.None: return BsResult[BsRingProof](error: normalized.error)
  # A negative index cannot wrap into an unsigned native position.
  if index < 0: return BsResult[BsRingProof](error: BsError.InvalidLength)
  var output: array[784, byte]
  let reason = error(nativeRingSign(handle(setup), handle(key), csize_t(index), data(
      normalized.value), csize_t(normalized.value.len), data(context), csize_t(context.len), data(
      additional), csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsRingProof](error: reason)
  BsResult[BsRingProof](error: BsError.None, value: BsRingProof(output))

# Verify root-bound ring proof using explicit domain/SRS parameters; failed proofs expose no output hash.
proc verifyRing*(setup: BsSetup, root: BsRingRoot, signature: BsRingProof, context,
    additional: openArray[byte]): BsResult[BsOutput] {.raises: [], gcsafe.} =
  var commitment = array[144, byte](root)
  var proof = array[784, byte](signature)
  var output: array[32, byte]
  let reason = error(nativeRingVerify(handle(setup), addr commitment[0], addr proof[0], 784, data(
      context), csize_t(context.len), data(additional), csize_t(additional.len), addr output[0]))
  # Failed native operations have no public scratch/default value to use.
  if reason != BsError.None: return BsResult[BsOutput](error: reason)
  BsResult[BsOutput](error: BsError.None, value: BsOutput(output))

# Own an exact fixed encoding; cryptographic validity is checked only during verification.
proc importSignature*(input: openArray[byte]): BsResult[BsSignature] {.raises: [], gcsafe.} =
  # Wrong widths fail before constructing a typed default or truncating trailing bytes.
  if input.len != 96: return BsResult[BsSignature](error: BsError.InvalidLength)
  var output: array[96, byte]
  # Copy all public bytes into independent owned storage.
  for i in 0..<96: output[i] = input[i]
  BsResult[BsSignature](error: BsError.None, value: BsSignature(output))

# Own an exact fixed encoding; cryptographic validity is checked only during verification.
proc importRingProof*(input: openArray[byte]): BsResult[BsRingProof] {.raises: [], gcsafe.} =
  # Wrong widths fail before constructing a typed default or truncating trailing bytes.
  if input.len != 784: return BsResult[BsRingProof](error: BsError.InvalidLength)
  var output: array[784, byte]
  # Copy all public bytes into independent owned storage.
  for i in 0..<784: output[i] = input[i]
  BsResult[BsRingProof](error: BsError.None, value: BsRingProof(output))

# Own an exact fixed encoding; cryptographic validity is checked only during verification.
proc importRingRoot*(input: openArray[byte]): BsResult[BsRingRoot] {.raises: [], gcsafe.} =
  # Wrong widths fail before constructing a typed default or truncating trailing bytes.
  if input.len != 144: return BsResult[BsRingRoot](error: BsError.InvalidLength)
  var output: array[144, byte]
  # Copy all public bytes into independent owned storage.
  for i in 0..<144: output[i] = input[i]
  BsResult[BsRingRoot](error: BsError.None, value: BsRingRoot(output))
