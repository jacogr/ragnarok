# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only PKCS8 serialization and actual bundled TLS self-signing bind the genuine computed roster's known seed to a private WorkSigner without exposing a production seed constructor.

import std/[assertions, base64, syncio]
import ../../src/crypto/primitives
import ../../src/jamnp-s/protocol

proc certificate(key: ptr byte, length: csize_t, dns: cstring, days: cint,
    pem: ptr byte, capacity: csize_t, written: ptr csize_t): cint {.importc: "rq_identity_cert",
        cdecl, header: "cert_fields.h".}
  ## Bundled TLS creates a real Ed25519 certificate using the exact test-owned PEM key and NP DNS identity.

proc assuranceSignerFiles*(keyPath, certificatePath: string, marker = 12'u8) {.raises.} =
  ## Independent literal DER framing wraps one fixed test seed; all private fixture material lives only under the runner's test-owned paths.
  var seed = default(array[32, byte])
  seed[0] = marker
  let imported = importSeed(seed)
  assert imported.error == CryptoError.None, "test seed import"
  let public = imported.value.publicKey
  assert public.error == CryptoError.None, "test TLS public identity"
  var der: seq[byte] = @[48'u8, 46, 2, 1, 0, 48, 5, 6, 3, 43, 101, 112, 4, 34, 4, 32]
  for octet in seed: der.add(octet) # PKCS8 v0, id-Ed25519 and nested OCTET STRING contain exactly32 test bytes.
  var key = "-----BEGIN PRIVATE KEY-----\n" & base64.encode(der) & "\n-----END PRIVATE KEY-----\n"
  var output = default(array[4096, byte])
  var written = csize_t(0)
  var dns = ""
  for octet in peerName(array[32, byte](public.value)): dns.add(char(octet))
  assert certificate(cast[ptr byte](key.toCString()), csize_t(key.len), dns.toCString(), 1,
    addr output[0], csize_t(output.len), addr written) == 1, "actual TLS self-signed certificate"
  assert written > 0 and written <= csize_t(output.len), "bounded certificate output"
  var pem = ""
  for index in 0..<int(written): pem.add(char(output[index]))
  writeFile(keyPath, key)
  writeFile(certificatePath, pem)
