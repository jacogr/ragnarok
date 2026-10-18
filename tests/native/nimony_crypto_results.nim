# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated default/failed crypto payload reads must stop at the success contract before using bytes or owners.
import std/[cmdline, syncio]
import ../../src/crypto/primitives
# Fault injection exists only in the separately linked test observer.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
let useDefault = paramStr(2) == "default"
let seed = importSeed(default(array[32, byte])).value
# Cleared and absent handles must remain distinct failures from an explicitly imported all-zero seed.
let cleared = importSeed(default(array[32, byte])).value
clearSeed(cleared)
fail(15)
case paramStr(1)
of "blake":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[Blake2bHash]) else: blake2b256([])
  echo array[32, byte](parsed.value)[0]
of "keccak":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[KeccakHash]) else: keccak256([])
  echo array[32, byte](parsed.value)[0]
of "seed-width":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdSeed]) else: importSeed([])
  echo ord(publicKey(parsed.value).error)
of "key-width":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdPublicKey]) else: importPublicKey([])
  echo array[32, byte](parsed.value)[0]
of "signature-width":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdSignature]) else: importSignature([])
  echo array[64, byte](parsed.value)[0]
of "key-missing":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdPublicKey]) else: publicKey(default(EdSeed))
  echo array[32, byte](parsed.value)[0]
of "key-cleared":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdPublicKey]) else: publicKey(cleared)
  echo array[32, byte](parsed.value)[0]
of "key-backend":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdPublicKey]) else: publicKey(seed)
  echo array[32, byte](parsed.value)[0]
of "sign-missing":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdSignature]) else: sign(default(EdSeed), [])
  echo array[64, byte](parsed.value)[0]
of "sign-cleared":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdSignature]) else: sign(cleared, [])
  echo array[64, byte](parsed.value)[0]
of "sign-backend":
  # Failed/default operations cannot authorize a fixed value or retained secret owner.
  let parsed = if useDefault: default(CryptoResult[EdSignature]) else: sign(seed, [])
  echo array[64, byte](parsed.value)[0]
else:
  # Unknown selectors are harness errors, never successful rejection evidence.
  quit(2)
