# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact full-node database identity binds a physical schema to an explicit caller-supplied chain.
## Checksums detect corruption; independently expected chain identity prevents accidental reuse.

import std/assertions
import ../crypto/primitives as crypto_primitives
import ../codec/bounded as codec_bounded

const
  IdentityMagic = "RAGNAROK-FULL-NODES-V1\n"
  ContextMagic = "RAGNAROK-FULL-STATE-V1\n"
  IdentityPrefix = IdentityMagic.len + 32
  StorageIdentityBytes* = IdentityPrefix + 32

type
  StorageSchema* {.pure.} = enum ## Distinct physical formats never silently reinterpret each other.
    FullNodesV1, FullStateV1
  StorageChecksum* = distinct array[32, byte] ## Local file integrity checksum is not a JAM commitment or chain identity.
  StorageChainId* = distinct array[32, byte] ## Storage chain identity is not a state root or protocol block hash.
  DatabaseIdentity* = object ## Opaque initialized full-state schema identity; no light-state APIs are implied.
    chain: StorageChainId
    schema: StorageSchema
    initialized: bool
  IdentityError* {.pure.} = enum ## No default/failed codec operation exposes initialized identity metadata.
    Uninitialized, None, InvalidFormat, LimitExceeded, ChecksumMismatch, WrongChain, BackendFailure
  IdentityResult*[T] = object ## Private alternatives expose only success or its exact refusal.
    case status: IdentityError
    of None: completed: T
    else: discard

func error*[T](outcome: IdentityResult[T]): IdentityError =
  ## Inspect a refusal without granting payload access.
  outcome.status
func value*[T](outcome: IdentityResult[T]): T {.inline,
    requires: outcome.status == IdentityError.None.} =
  ## Extract only complete checked bytes or an initialized identity.
  outcome.completed
func fullStateIdentity*(chain: StorageChainId, schema = StorageSchema.FullNodesV1): DatabaseIdentity =
  ## Bind the full-state schema to an explicit scalar chain identity without IO or defaults.
  DatabaseIdentity(chain: chain, schema: schema, initialized: true)
func chainId*(identity: DatabaseIdentity): StorageChainId {.requires: identity.initialized.} =
  ## Copy the identity domain without exposing initialization or mutable storage fields.
  identity.chain
proc encodeDatabaseIdentity*(identity: DatabaseIdentity, limit: ByteLimit): IdentityResult[seq[byte]] =
  ## Hash one fixed prefix only after lifecycle and output-byte preflight.
  if not identity.initialized: return IdentityResult[seq[byte]](status: IdentityError.Uninitialized)
  if uint64(limit) < uint64(StorageIdentityBytes): return IdentityResult[seq[byte]](
      status: IdentityError.LimitExceeded)
  var prefix = default(array[IdentityPrefix, byte])
  let magic = if identity.schema == StorageSchema.FullNodesV1: IdentityMagic else: ContextMagic
  for i, character in magic: prefix[i] = byte(character) # Full-state mode/schema has one exact domain.
  let chain = array[32, byte](identity.chain)
  for i in 0..<32: prefix[IdentityMagic.len+i] = chain[i]
  let hashed = blake2b256(prefix)
  if hashed.error != CryptoError.None: return IdentityResult[seq[byte]](
      status: IdentityError.BackendFailure)
  var output = newSeq[byte](StorageIdentityBytes)
  for i, octet in prefix: output[i] = octet
  let checksum = array[32, byte](hashed.value)
  for i in 0..<32: output[IdentityPrefix+i] = checksum[i]
  IdentityResult[seq[byte]](status: IdentityError.None, completed: output)
proc decodeDatabaseIdentity*(input: openArray[byte], expected: StorageChainId,
    limit: ByteLimit, schema = StorageSchema.FullNodesV1): IdentityResult[DatabaseIdentity] =
  ## Refuse unknown mode/schema, exact-width corruption and a different independently selected chain.
  if uint64(input.len) > uint64(limit): return IdentityResult[DatabaseIdentity](
      status: IdentityError.LimitExceeded)
  if input.len != StorageIdentityBytes: return IdentityResult[DatabaseIdentity](
      status: IdentityError.InvalidFormat)
  let magic = if schema == StorageSchema.FullNodesV1: IdentityMagic else: ContextMagic
  for i, character in magic:
    if input[i] != byte(character): return IdentityResult[DatabaseIdentity](
        status: IdentityError.InvalidFormat)
  var prefix = default(array[IdentityPrefix, byte])
  for i in 0..<prefix.len: prefix[i] = input[i] # Fixed shape is proved before all copied fields.
  let hashed = blake2b256(prefix)
  if hashed.error != CryptoError.None: return IdentityResult[DatabaseIdentity](
      status: IdentityError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for i in 0..<32:
    if input[IdentityPrefix+i] != checksum[i]: return IdentityResult[DatabaseIdentity](
        status: IdentityError.ChecksumMismatch)
  let chain = array[32, byte](expected)
  for i in 0..<32:
    if input[IdentityMagic.len+i] != chain[i]: return IdentityResult[DatabaseIdentity](
        status: IdentityError.WrongChain)
  IdentityResult[DatabaseIdentity](status: IdentityError.None, completed: fullStateIdentity(
      expected, schema))
