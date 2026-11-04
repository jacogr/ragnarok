# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private immutable local signer ownership matches the configured TLS identity; no raw seed or arbitrary-message signing API escapes.
import ./identity
import ../crypto/primitives
import ../quic/transport
import ../codec/bounded
import ../codec/state/safrole
import ../lib/atomic/file

type
  WorkSignerError* {.pure.} = enum ## Failed/default imports expose no signer or identity.
    Uninitialized, None, InvalidPath, CertificateFailure, ReadFailure, KeyFailure,
      KeyAllocationFailure, CryptoFailure, IdentityMismatch
  WorkSignerData = ref object ## Only private seed ownership survives startup; the final EdSeed release wipes its own storage.
    seed: EdSeed
    identity: StateEdKey
  WorkSigner* = object ## Caller cannot obtain a mutable clearable seed alias; managed jobs must freeze this private owner until exact collection/join.
    data: nil WorkSignerData
  WorkSignerResult*[T] = object ## Only complete success carries an owner or copied public identity; genuine children retain selected reasons.
    case status: WorkSignerError
    of None: completed: T
    of CertificateFailure: certificateReason: CertificateIdentityError
    of ReadFailure: readReason: AtomicFileError
    of CryptoFailure: cryptoReason: CryptoError
    else: discard # No partial private key survives a local refusal.
func error*[T](outcome: WorkSignerResult[T]): WorkSignerError =
  ## Inspect a reason without permitting writable discriminator access.
  outcome.status
func value*[T](outcome: WorkSignerResult[T]): T {.requires: outcome.status ==
    WorkSignerError.None.} =
  ## Extract only completely imported private ownership or public copied facts.
  outcome.completed
func certificateError*[T](outcome: WorkSignerResult[
    T]): CertificateIdentityError {.requires: outcome.status ==
    WorkSignerError.CertificateFailure.} =
  ## Retain the exact bounded leaf-certificate refusal.
  outcome.certificateReason
func readError*[T](outcome: WorkSignerResult[T]): AtomicFileError {.requires: outcome.status ==
    WorkSignerError.ReadFailure.} =
  ## Retain the exact bounded private-file read refusal.
  outcome.readReason
func cryptoError*[T](outcome: WorkSignerResult[T]): CryptoError {.requires: outcome.status ==
    WorkSignerError.CryptoFailure.} =
  ## Preserve the actual private seed/public-key backend refusal.
  outcome.cryptoReason
proc signerIdentity*(signer: WorkSigner): WorkSignerResult[StateEdKey] =
  ## Copy only public bytes; a default or refused signer carries no fabricated all-zero identity.
  let data = signer.data
  if data == nil: return WorkSignerResult[StateEdKey](status: WorkSignerError.Uninitialized)
  WorkSignerResult[StateEdKey](status: WorkSignerError.None, completed: data.identity)
func validSignerPath(path: string): bool =
  ## Bound path conversion independently from caller CLI policy and reject NUL truncation before any file operation.
  if path.len == 0 or path.len > 4096: return false
  for character in path:
    if character == char(0): return false
  true
proc loadWorkSigner*(certificate, privateKey: string): WorkSignerResult[WorkSigner] =
  ## Bounded startup reads and maintained PEM parsing never prompt or log secrets; all caller scratch is explicitly wiped.
  if not validSignerPath(certificate) or not validSignerPath(privateKey):
    return WorkSignerResult[WorkSigner](status: WorkSignerError.InvalidPath)
  let expected = certificateIdentity(certificate)
  if expected.error != CertificateIdentityError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.CertificateFailure,
        certificateReason: expected.error)
  var pem = default(array[65537, byte])
  defer: clearSecret(pem)
  let loaded = readFileInto(privateKey, pem)
  if loaded.error != AtomicFileError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.ReadFailure,
        readReason: loaded.error)
  if loaded.value == 0: return WorkSignerResult[WorkSigner](status: WorkSignerError.KeyFailure)
  var raw = default(array[32, byte])
  defer: clearSecret(raw)
  let parsed = parseIdentitySeed(addr pem[0], csize_t(loaded.value), addr raw[0])
  if parsed < 0: return WorkSignerResult[WorkSigner](status: WorkSignerError.KeyAllocationFailure)
  if parsed != 1:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.KeyFailure)
  let imported = importSeed(raw)
  if imported.error != CryptoError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.CryptoFailure,
        cryptoReason: imported.error)
  let derived = imported.value.publicKey
  if derived.error != CryptoError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.CryptoFailure,
        cryptoReason: derived.error)
  if array[32, byte](derived.value) != array[32, byte](expected.value):
    return WorkSignerResult[WorkSigner](status: WorkSignerError.IdentityMismatch)
  WorkSignerResult[WorkSigner](status: WorkSignerError.None, completed: WorkSigner(data:
    WorkSignerData(seed: imported.value, identity: expected.value)))
