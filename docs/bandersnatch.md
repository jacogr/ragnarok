# Bandersnatch APIs and reproduction

Both languages call the same project-maintained Rust/C ABI. The
[pinned interpretation](../spec/bandersnatch.md) explains the historical suite,
SRS, guards and remaining audit gates. [Observed results](../results/bandersnatch.md)
record the concrete checks.

| Nim (`nim/bandersnatch/bandersnatch`) | Odin (`odin/bandersnatch`) | Result |
| --- | --- | --- |
| `importScalar(bytes)` | `import_scalar(bytes)` | Opaque owned canonical nonzero scalar, not a seed |
| `publicKey(key)` | `public_key(key)` | Distinct owned 32-byte public key |
| `importPublicKey(bytes)` | `import_public_key(bytes)` | Checked canonical/subgroup public encoding |
| `sign(key, context, additional)` | `sign(key, context, additional)` | Distinct 96-byte signature |
| `verify(key, signature, context, additional)` | `verify(key, signature, context, additional)` | Distinct verified 32-byte output |
| `newSetup(capacity)` | `new_setup(capacity)` | Opaque immutable SRS/domain owner |
| `commitRing(setup, members)` | `commit_ring(setup, members)` | Distinct 144-byte root |
| `signRing(setup, key, index, members, context, additional)` | `sign_ring(setup, key, index, members, context, additional)` | Distinct 784-byte proof |
| `verifyRing(setup, root, proof, context, additional)` | `verify_ring(setup, root, proof, context, additional)` | Distinct verified 32-byte output |
| `importSignature`, `importRingProof`, `importRingRoot` | `import_signature`, `import_ring_proof`, `import_ring_root` | Exact-width owned public encodings |
| `close(key)`, `close(setup)` or final ARC release | `destroy_key(&key)`, `destroy_setup(&setup)` | Release through original Rust allocator |

Nim checks `result.error == BsError.None` before `result.value`. Odin checks
`error_of(result) == .None` before `success_of(result)`. Defaults fail; failed
operations contain only a reason. Verification failure has no output hash.
Public nominal key/output types and key/setup owner types cannot be assigned
implicitly across roles.

## Ownership

Rust retains scalar/key and public parameter allocations; neither language can
inspect their layouts or mutable members. The scalar is canonical imported
material, not a 32-byte random seed interpreted through an invented KDF. The
original secret input and its copies remain caller-owned and require their own
lifetime/erasure handling. The backend zeroizes the retained scalar on drop;
this is not a promise to erase every stack/register/backend temporary.

Nim wraps native pointers in private acyclic ARC storage. Aliases retain that
storage; last-reference release invokes the matching Rust destructor. Explicit
close releases once and nils the shared pointer, so all retained aliases
subsequently fail. No alias may race close with a call. Do not pass mutable ARC
owners across threads; tests import independent worker owners.

Odin uses distinct opaque native handles. Exactly one release owner destroys
and nils the passed handle; copies are borrowed aliases that must never be used
or released after destruction. Rust's allocator owns these allocations; Odin's
allocator owns only its transient normalized-member copies and fixture buffers.
Those copies are scoped and deleted through the current allocator. Setup owners
must outlive every call using their domain/SRS. No owner may be forged or freed
while a native call borrows it.

Raw context/additional/member buffers are borrowed synchronously and must stay
stable during the call. Output signatures, roots and verified hashes own bytes.
Protocol domains, context composition, attempt bytes and codec serialization
remain native language/application responsibilities. The Rust ABI neither
retains caller buffers nor constructs JAM ticket/seal messages.

## Reproduce

```sh
python3 tools/format.py --check
python3 interoperability/test_bandersnatch.py --fetch
```

The first run initializes pinned source submodules and obtains Cargo's locked
registry packages. Official fixture originals and the SRS are read directly from
their submodules; see [the source guide](dependencies.md). Source-tree, SRS,
lockfile, fixture and official-reduction hashes are checked. Native builds/tests
then run with `--locked --offline`. Subsequent runs can omit `--fetch`. No source
patches or fetched setup/vector-generation scripts run. Dependency build scripts
were inspected for compiler-version/probe behavior and build-output-only writes;
this review is not a cryptographic audit.

The runner requires Rust/Cargo 1.99.0 and rustfmt. This matches the installed
local toolchain and supports the Rust 2024 backend; existing Nim/Odin pins stay
unchanged. Linux CI installs that exact official toolchain with rustfmt through
rustup's component verification, and runs the new suite before QUIC. Its new step
awaits a pushed run. Shared libraries/binaries are build-tree test artifacts,
not relocatable production packages.
