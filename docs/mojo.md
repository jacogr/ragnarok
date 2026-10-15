# Mojo evaluation

Mojo is the third independent candidate for the existing M1/M2/M3 POC, using stable
**Mojo 1.1.0 (8189361e)**. The maintainer explicitly accepted the same callback/readiness
networking standard as Odin. A future supported task runtime may offer another implementation
path; it is not needed for this adapter.

## Reproduce

Use Python 3.12+ to install the SDK and its official formatter in an isolated environment:

```sh
python3 -m venv build/mojo-env
build/mojo-env/bin/python -m pip install --require-hashes -r tools/mojo-requirements.txt
build/mojo-env/bin/mojo --version
python3 tools/format.py
```

The lock includes compiler, standard libraries and formatter wheel hashes for supported Mac/Linux
platforms. `interoperability/mojo_support.py` rejects a different compiler build identity.
`RAGNAROK_MOJO` may explicitly select the same pinned compiler elsewhere.

```sh
python3 interoperability/test_codec.py --mojo
python3 interoperability/test_crypto.py --mojo --fetch
python3 interoperability/test_bandersnatch.py --mojo --fetch
python3 interoperability/test_quic.py --mojo --fetch
python3 interoperability/test_quic_soak.py --mojo --skip-build
python3 interoperability/test_quic_service.py --mojo --skip-build
python3 interoperability/test_quic_mesh.py --mojo --skip-build
python3 interoperability/test_quic_resilience.py --mojo --skip-build
python3 interoperability/test_integration.py --mojo --reuse-native
python3 interoperability/test_quic_offload.py --mojo --reuse-native
python3 interoperability/benchmark.py --mojo --reuse-native
```

`--mojo` includes Nim and Odin in the same shared tests. Networking matrices expand to all nine
directed pairings. Integrated and offload binaries are separately labelled and linked. Test
controllers use Python; the compiled candidate codec/crypto/networking paths do not use Python.
Local `otool -L` checks show the SDK's `libKGENCompilerRTShared` plus the maintained native
libraries and system libc, with no Python library. Deploying these binaries also requires the
matching pinned SDK runtime library; it is a dependency distinct from the Python build tooling.
The Linux workflow runs these commands and retains their diagnostics. A local pass does not
establish a Linux pass; inspect the subsequent GitHub Actions run.

## Implementation and ownership

`mojo/codec` implements the established scalar, bounded, composite and C.2 digest contracts.
Nominal parameterized types separate indices, widths, limits, hashes and metrics. Checked results
wrap the public `Variant` API; failures contain only a reason code and default results fail.
Success extraction requires selecting the correct alternative, including in optimized builds.
Borrowed encoders preflight capacity, limits and overlap before committing bytes.

Opaque owned snapshots copy their validated input and bind extraction/re-encoding to that owner.
They expose no mutable snapshot buffer or detached payload span. Foreign-owned snapshot, Ed25519
seed and Bandersnatch handles have one explicit release owner; copies are aliases, as with Odin.
Releasing an owner invalidates its aliases. This is a documented lifetime contract, not
compiler-enforced affine ownership. Mojo underscore names are a convention, not access control;
explicit unsafe pointer operations remain capable of violating these contracts.

`mojo/crypto` uses the existing BoringSSL/XKCP ABI for Blake2b-256, Ed25519 and legacy Keccak-256.
`mojo/bandersnatch` uses the unchanged pinned historical Rust adapter for contextual and ring VRFs,
with native ring normalization/domain policy. It preserves owned secret wiping, checked failures,
setup/key lifetime and same-process multi-thread checks. Ed25519 follows the BoringSSL acceptance
policy already observed in Nim, including the documented identity-point difference from Odin.

`mojo/quic` implements identity policy, framing, stream ownership, admission, peer arbitration,
cancellation and job scheduling in Mojo over the same maintained LSQUIC ABI. The C helper under
`interoperability/mojo` supplies socket/record layouts, public OS synchronization and heap
observations. It contains no JAM decoder, identity policy, queue or application scheduler.
Certificate offsets come from the C compiler's `sizeof`/`offsetof` observations and are checked
before loads. Stable callback owners outlive synchronous callbacks and engine destruction.

One POSIX readiness dispatcher drives each logical peer's retained role engines. Two fixed
pthread workers process the optional bounded Bandersnatch queue; no connection/stream creates a
thread. There are no private SDK task/runtime calls, compiler IR injections, upstream patches,
per-stream workers or replacement C protocol implementations.

## Measurement differences

On this Mac, the SDK creates nine startup threads in the native readiness probe. The harness
measures that baseline before each run, retains raw process counts, and rejects growth above it;
the proof-worker build has eleven threads. Shutdown heap baselines use a bounded pre-endpoint
quiescent window so SDK startup allocations cannot race the final comparison. The 64 KiB shutdown
limit remains after engine destruction and for the lifecycle soak. During retained-engine operation,
process malloc uses the same 16 MiB aggregate growth budget as RSS; Nim/Odin application counters
retain their 64 KiB limit. These scopes have different leak-detection sensitivity. Reports include
the selected scope and ceiling. See the [CI investigation](../results/mojo-service-ci.md).
Linux measures its own baseline rather than assuming Mac counts. These fixed runtime threads and their memory cost remain language-decision inputs.

Mojo's public API does not provide the allocator call/free counters used by the other adapters.
Its separate benchmark instrumentation records public process malloc live-byte deltas and RSS,
including SDK/native-library allocations. Call/free/requested-byte counts are explicitly null,
not estimated from those observations. Ownership correctness instead has snapshot mutation,
release, bounded-service growth and shutdown checks. Microbenchmark process heap observations
can include SDK initialization/cache activity; they do not establish per-operation allocation
freedom. Borrowed codecs themselves use bounded scalar/array storage without owned payload copies.

The timing binary uses the shared opaque observation boundary and public OS monotonic clock:
Linux `clock_gettime`, macOS `mach_absolute_time` with the public timebase. This avoids observed
microsecond quantization of the SDK clock for short Mac calls. Timing and heap instrumentation
are separate binaries. The 69 common case/operation pairs and independent fingerprints are
unchanged; measurements are a baseline, with no speed optimization or winner threshold.

## Scope

Parity means the existing bounded POC features and fixtures. General multi-target validator
networking, independent JAM stacks, full-ring production sizing, backend/security review and
consensus implementation remain shared future work. Passing this POC does not select a language
or claim production readiness. Mojo's smaller ecosystem, explicit FFI lifetime work and toolchain
maturity remain qualitative evaluation inputs alongside measured correctness/resources/speed.
