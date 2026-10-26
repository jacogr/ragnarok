# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published JIP-5 development/random-seed goldens, ownership and exact-width refusals.
import std/[assertions, syncio]
import ../../native/batch_support
import ../../../src/crypto/[primitives, validator_keys]
import ../../../src/bandersnatch/bandersnatch

# Failure injection remains confined to the observer-linked native test process.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}

proc decoded(text: string): array[32, byte] =
  ## Decode fixed test literals without deriving expected keys through the implementation under test.
  assert text.len == 64
  result = default(array[32, byte])
  for i in 0..<32:
    result[i] = octet(text[i*2..i*2+1])

const EdSeeds = [
  "996542becdf1e78278dc795679c825faca2e9ed2bf101bf3c4a236d3ed79cf59",
  "b81e308145d97464d2bc92d35d227a9e62241a16451af6da5053e309be4f91d7",
  "0093c8c10a88ebbc99b35b72897a26d259313ee9bad97436a437d2e43aaafa0f",
  "69b3a7031787e12bfbdcac1b7a737b3e5a9f9450c37e215f6d3b57730e21001a",
  "b4de9ebf8db5428930baa5a98d26679ab2a03eae7c791d582e6b75b7f018d0d4",
  "4a6482f8f479e3ba2b845f8cef284f4b3208ba3241ed82caa1b5ce9fc6281730",
  "f21e2d96a51387f9a7e5b90203654913dde7fa1044e3eba5631ed19f327d6126"]
const EdPublic = [
  "4418fb8c85bb3985394a8c2756d3643457ce614546202a2f50b093d762499ace",
  "ad93247bd01307550ec7acd757ce6fb805fcf73db364063265b30a949e90d933",
  "cab2b9ff25c2410fbe9b8a717abb298c716a03983c98ceb4def2087500b8e341",
  "f30aa5444688b3cab47697b37d5cac5707bb3289e986b19b17db437206931a8d",
  "8b8c5d436f92ecf605421e873a99ec528761eb52a88a2f9a057b3b3003e6f32a",
  "ab0084d01534b31c1dd87c81645fd762482a90027754041ca1b56133d0466c06",
  "11a695f674de95ff3daaff9a5b88c18448b10156bf88bc04200e48d5155c7243"]
const BsSeeds = [
  "007596986419e027e65499cc87027a236bf4a78b5e8bd7f675759d73e7a9c799",
  "12ca375c9242101c99ad5fafe8997411f112ae10e0e5b7c4589e107c433700ac",
  "3d71dc0ffd02d90524fda3e4a220e7ec514a258c59457d3077ce4d4f003fd98a",
  "107a9148b39a1099eeaee13ac0e3c6b9c256258b51c967747af0f8749398a276",
  "0bb36f5ba8e3ba602781bb714e67182410440ce18aa800c4cb4dd22525b70409",
  "75e73b8364bf4753c5802021c6aa6548cddb63fe668e3cacf7b48cdb6824bb09",
  "06154d857537a9b622a9a94b1aeee7d588db912bfc914a8a9707148bfba3b9d1"]
const BsPublic = [
  "4fc1cc2146c5463a023a66d1fc72829025ef654f1e1dd5c917c40346c2b3aa06",
  "4d5c855aebc996a88e818acd27d995f8e04c5dc49652c349f3f3204b39f1984a",
  "60a294af38653b7f0073767a0b9d10d8bf0efa6804782a9ecd17a9f5fd323b5b",
  "1e50be41fa601015847ae50ef0946ba5217027653d0ffd7a879c45ca21bab357",
  "b9b83ef77c1fda8f4b2909e531e6842bf26d4e6f69ed1405fc8d12d1350e6265",
  "7ef0acbb01d1ad5da7a1b576aef6ea9a91b979612ff339970c69fe0004d68e05",
  "7273ec723f5f99e8ecb0d00417d0138eee582c1e0effbdfb38a425572d815009"]

proc main() =
  ## End-to-end public keys pin JIP-5's current Draft 35 transcript-based seed derivation.
  for index in 0..6:
    let master = if index < 6: trivialSeed(uint32(index)) else:
      decoded("f92d680ea3f0ac06307795490d8a03c5c0d4572b5e0a8cffec87e1294855d9d1")
    let ed = deriveEd25519Seed(master)
    assert ed.error == CryptoError.None
    let public = publicKey(ed.value)
    assert public.error == CryptoError.None
    assert array[32, byte](public.value) == decoded(EdPublic[index])
    let exported = exportPkcs8(ed.value)
    assert exported.error == CryptoError.None
    let expected = decoded(EdSeeds[index])
    for i in 0..<32:
      assert exported.value[i+16] == expected[i] # Exported seed bytes match the published domain digest.
    let bs = deriveBandersnatchKey(master)
    assert bs.error == BsError.None
    let bsPublic = publicKey(bs.value)
    assert bsPublic.error == BsError.None
    assert array[32, byte](bsPublic.value) == decoded(BsPublic[index])
    let imported = importSecretSeed(decoded(BsSeeds[index]))
    assert imported.error == BsError.None
    assert array[32, byte](publicKey(imported.value).value) == array[32, byte](bsPublic.value)
    let message = [1'u8, 2, 3]
    let signature = sign(ed.value, message)
    assert signature.error == CryptoError.None
    assert verify(public.value, signature.value, message)
    let proof = sign(bs.value, message, [])
    assert proof.error == BsError.None
    assert verify(bsPublic.value, proof.value, message, []).error == BsError.None
    let alias = ed.value
    clearSeed(ed.value)
    assert publicKey(alias).error == CryptoError.InvalidSeed
    assert exportPkcs8(alias).error == CryptoError.InvalidSeed
    assert exported.value[16] == expected[0] # Explicit export owns its independent secret bytes.
    close(bs.value)
    close(imported.value)
  let multi = trivialSeed(0x01020304'u32)
  for i in 0..<32:
    assert multi[i] == [4'u8, 3, 2, 1][i mod 4] # Test all four bytes, not only indices below256.
  let last = trivialSeed(high(uint32))
  for octet in last:
    assert octet == 255
  for length in [0, 31, 33]:
    let malformed = newSeq[byte](length)
    assert deriveEd25519Seed(malformed).error == CryptoError.InvalidLength
    assert deriveBandersnatchKey(malformed).error == BsError.InvalidLength
    assert importSecretSeed(malformed).error == BsError.InvalidLength
  var scratch = trivialSeed(high(uint32))
  clearSecret(scratch)
  assert scratch == default(array[32, byte])
  var empty: seq[byte] = @[]
  clearSecret(empty) # Empty secret scratch must not evaluate element zero.
  fail(1)
  assert deriveEd25519Seed(trivialSeed(0)).error == CryptoError.BackendFailure
  assert deriveBandersnatchKey(trivialSeed(0)).error == BsError.BackendFailure
  var untouched = trivialSeed(high(uint32))
  assert blake2b256([], untouched) == CryptoError.BackendFailure
  assert untouched == trivialSeed(high(uint32))
  fail(0)
  assert exportPkcs8(default(EdSeed)).error == CryptoError.InvalidSeed
main()
echo "PASS validator keys: JIP-5 published identities, exact domains, Draft 35 derivation, owned exports and refusals"
