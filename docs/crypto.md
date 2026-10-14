# Primitive APIs and ownership

The first M2 slice supplies Blake2b-256, Ed25519 and legacy Keccak-256.
[Specification interpretation](../spec/crypto.md) and
[verification report](../results/crypto-primitives.md) describe the limits.

| Nim (`nim/crypto/primitives`) | Odin (`odin/crypto`) | Output |
| --- | --- | --- |
| `blake2b256(bytes)` | `blake2b256(bytes)` | Checked distinct 32-byte Blake2b hash |
| `keccak256(bytes)` | `keccak256(bytes)` | Checked distinct 32-byte Keccak hash |
| `importSeed(bytes)` | `import_seed(bytes, allocator)` | Checked opaque retained seed |
| `publicKey(seed)` | `public_key(seed)` | Checked distinct 32-byte public key |
| `sign(seed, message)` | `sign(seed, message)` | Checked distinct 64-byte signature |
| `importPublicKey(bytes)` | `import_public_key(bytes)` | Checked owned public encoding |
| `importSignature(bytes)` | `import_signature(bytes)` | Checked owned signature encoding |
| `verify(key, sig, message)` | `verify(key, sig, message)` | Boolean backend verdict |
| `clearSeed(seed)` | `clear_seed(seed)` | Wipe retained bytes and invalidate aliases |
| ARC last-handle release | `destroy_seed(&seed)` | Wipe/free private retained storage |

Check `result.error == CryptoError.None` before selecting Nim `result.value`.
For Odin check `error_of(result) == .None`, then select `success_of(result)`.
A failed result has no value. Default and cleared seeds yield `InvalidSeed`
(`.Invalid_Seed`), independently of the bytes of a valid explicitly imported
zero seed. Public/signature imports require exact sizes and copy all bytes.
Verification may return false for a correctly sized invalid encoding. The
providers currently disagree for a small-order identity public key with
identity-R, zero-S signatures: BoringSSL accepts, Odin rejects. This is exposed
in regression tests and is an unresolved JAM acceptance-policy gate; see the
[pinned interpretation](../spec/crypto.md).

## Seed lifetime

Nim's opaque object retains a private acyclic ARC reference. Copies share that
reference. Clear invalidates every alias; final release invokes explicit
cleansing before freeing. Do not mutate/clear one seed concurrently with its
operations. Workers in the tests import independent owners.

Odin allocates private storage through the supplied allocator, which must
outlive the owner. Exactly one owner calls `destroy_seed`; copied handles are
borrowed aliases, not compiler-enforced unique owners. Clear invalidates all
aliases without freeing. Destroy wipes the storage, frees it through its
original allocator and nils the passed handle. Other aliases must never be
used or destroyed afterwards. A nil owner can be cleared/destroyed harmlessly.
Do not share a mutable seed owner between threads.

Input arrays are borrowed synchronously and must stay stable during each call.
Import creates an independent seed copy; changing/releasing the input afterwards
does not change the key. The caller still owns and must manage the original
secret input and any of its copies. Public outputs are independent fixed arrays.

The bridge holds no caller pointers, callbacks or global mutable hash contexts.
Nim's bridge cleanses its expanded 64-byte private-key scratch; Odin clears its
local core private key on all return paths. This does not promise erasure of
every compiler/backend stack/register copy or process dumps. Key generation,
entropy, keystores and production-secret handling are later integration work;
no insecure random-key API is provided here.

Wrong lengths and cleared/missing owners fail explicitly. Odin allocator refusal
returns `.Allocation_Failure`; Nim's ARC allocation exhaustion follows Nim's
runtime OutOfMemDefect policy and is not represented as a recoverable result.
Backend signing failures produce a payload-free failure. Calling a success
selector on a failure is programmer misuse and traps in the checked builds.

## Reproduce

```sh
python3 tools/format.py --check
python3 interoperability/test_crypto.py --fetch
```

`--fetch` obtains only missing pinned BoringSSL/XKCP sources inside ignored
`build/`; it installs no global package and applies no source patches. Subsequent
runs can omit the flag. The runner compiles debug and optimized binaries and
executes all tests. BoringSSL sources/build are shared with the identical QUIC
pin. No LSQUIC dependency or UDP service is needed for crypto tests. The Nim
shared library lives under `build/crypto`; generated binaries link that absolute
build location and are test artifacts, not relocatable release packages.

Linux CI invokes the runner before QUIC and retains only explicit logs/results.
Public RFC test seeds are fixtures, not production credentials. Bandersnatch
compatibility/Rust ABI evaluation is the next separate bounded round.
