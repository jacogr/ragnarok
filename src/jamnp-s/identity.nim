# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded public leaf-certificate identity and pinned JAMNP-S preferred-initiator selection.

import std/[base64, assertions]
import ../lib/atomic/file
import ../codec/bounded
import ../codec/state/safrole
import ../quic/transport
import ./protocol

type
  CertificateIdentityError* {.pure.} = enum ## Missing or invalid public files carry no identity.
    Uninitialized, None, ReadFailed, InvalidPem, InvalidCertificate
  CertificateIdentityResult* = object ## Private guarded success contains only a fixed copied public key.
    case status: CertificateIdentityError
    of None: completed: StateEdKey
    else: discard # No private key material is read or retained.

func error*(outcome: CertificateIdentityResult): CertificateIdentityError =
  ## Inspect failure before identity extraction.
  outcome.status

func value*(outcome: CertificateIdentityResult): StateEdKey {.requires: outcome.status ==
    CertificateIdentityError.None.} =
  ## Extract only a complete validated public identity.
  outcome.completed

func space(value: byte): bool =
  ## PEM whitespace is ASCII and has no locale-dependent interpretation.
  value in [byte(' '), byte('\t'), byte('\r'), byte('\n')]

proc marker(bytes: seq[byte], position: int, expected: string): bool =
  ## Bound subtraction before comparing one fixed PEM delimiter.
  if position < 0 or position > bytes.len or expected.len > bytes.len-position: return false
  for index in 0..<expected.len:
    if bytes[position+index] != byte(expected[index]): return false # Exact delimiter only.
  true

proc certificateIdentity*(path: string): CertificateIdentityResult =
  ## Read a bounded public chain file and validate its first leaf, matching SSL_CTX's leaf selection.
  let read = readBoundedFile(path, ByteLimit(128*1024))
  if read.error != AtomicFileError.None:
    return CertificateIdentityResult(status: CertificateIdentityError.ReadFailed)
  let bytes = read.value
  const first = "-----BEGIN CERTIFICATE-----"
  const last = "-----END CERTIFICATE-----"
  var start = 0
  while start < bytes.len and space(bytes[start]): inc start # No unbounded trim allocation.
  if not marker(bytes, start, first): return CertificateIdentityResult(
      status: CertificateIdentityError.InvalidPem)
  start += first.len # The successful delimiter comparison proves this extent.
  var finish = start
  while finish < bytes.len and not marker(bytes, finish, last): inc finish
  if finish == bytes.len or finish-start > 16384:
    return CertificateIdentityResult(status: CertificateIdentityError.InvalidPem) # Bound base64 work before allocating a body.
  var body = ""
  for index in start..<finish:
    if not space(bytes[index]): body.add(char(bytes[
        index])) # Ignore only standard PEM whitespace inside this leaf.
  try:
    var der = base64.decode(body)
    if der.len == 0 or der.len > 8192 or base64.encode(der) != body:
      return CertificateIdentityResult(status: CertificateIdentityError.InvalidPem) # No alternate/prefix base64 representation.
    let raw = der.toCString()
    if not validPeer(cast[ptr byte](raw), csize_t(der.len), []):
      return CertificateIdentityResult(status: CertificateIdentityError.InvalidCertificate) # Reuse exact Ed25519/SAN policy.
    var fields {.noinit.}: CertFields
    if parseCert(cast[ptr byte](raw), csize_t(der.len), addr fields) != 1 or fields.edKey != 1 or
        fields.keyLength != 32:
      return CertificateIdentityResult(status: CertificateIdentityError.InvalidCertificate)
    var key = default(array[32, byte])
    for index in 0..<32: key[index] = fields.key[index] # Native success initializes the complete fixed field.
    CertificateIdentityResult(status: CertificateIdentityError.None, completed: StateEdKey(key))
  except:
    CertificateIdentityResult(status: CertificateIdentityError.InvalidPem) # Malformed public base64 cannot escape startup as an exception.

func preferredInitiator*(local, remote: StateEdKey): bool =
  ## Full lexicographic key comparison plus the two final-byte high bits from required connectivity.
  let left = array[32, byte](local)
  let right = array[32, byte](remote)
  var less = false
  for index in 0..<32:
    if left[index] != right[index]:
      less = left[index] < right[index]
      break # The first unequal octet alone selects lexicographic order.
  (left[31] > 127) xor (right[31] > 127) xor less
