# Linux CI

[The GitHub Actions workflow](../.github/workflows/linux.yml) runs on pushes,
pull requests and manual dispatches. It uses one Ubuntu 24.04 x86-64 runner;
there are no macOS or Windows CI jobs.

The job installs native build dependencies and the existing pinned Nim 2.2.12,
Odin dev-2026-10 and odinfmt 2026-08 toolchains into temporary runner storage.
[CI download pins](../spec/ci-toolchains.json) include SHA-256 checksums for each
archive and the formatter compatibility patch used by the macOS Homebrew build.
The official Odin Linux binary reports `dev-2026-10-nightly:84bc3fc`, with a
nightly suffix and shorter source hash than Homebrew. The shared test runners
accept this exact version only on Linux and only when the executable matches
the pinned SHA-256. Existing full revision checks remain. GitHub Actions are
pinned to the latest verified releases: checkout 7.0.1, setup-python 7.0.0 and
upload-artifact 7.0.2, all using Node 24.

Bandersnatch additionally uses pinned Rust/Cargo 1.99.0 and rustfmt, installed
through official rustup component verification in this temporary runner. The
Rust ABI's pristine historical backend/spec sources, Cargo.lock closure and
public SRS are independently pinned; no dependency source patches are applied.

After checkout, `python3 tools/setup_submodules.py` initializes the recorded
upstream source submodules and a focused JAM-vector checkout. Compiler setup
then proceeds as before. The job runs:

```sh
python3 tools/format.py --check
python3 interoperability/test_codec.py
python3 interoperability/test_crypto.py --fetch
python3 interoperability/test_bandersnatch.py --fetch
python3 interoperability/test_quic.py --fetch
python3 interoperability/test_quic_soak_harness.py
python3 interoperability/test_quic_soak.py --skip-build
python3 interoperability/test_quic_service.py --skip-build
python3 interoperability/test_integration.py --reuse-native
python3 interoperability/test_benchmark_harness.py
python3 interoperability/benchmark.py --reuse-native
```

The codec command covers both native implementations, negative compilation
fixtures, official vectors and shared conformance cases. The crypto command
checks both debug/release implementations, pinned RFC/Wycheproof fixtures,
independent hashes, ownership and concurrent native calls. It uses pristine
BoringSSL/XKCP submodules and shares the identical BoringSSL build with QUIC.
The new Bandersnatch step awaits a pushed Linux run. The QUIC command uses
pinned native submodules, builds both explicit adapters without Nim
packages/source patches, and runs the authenticated
cross-language CE 143 proof and rejection cases. Dependencies are not cached.
The new bounded soak follows the original proof using those freshly built peers;
see [its workload and budgets](quic-soak.md). Python 3.12 supports safe archive
extraction during setup.

Odin's Linux `core:nbio` backend uses io_uring. The workflow enables it through
optional kernel policy settings on this temporary runner before testing.
See [the QUIC proof instructions](quic-proof.md) for native dependencies,
protocol pins, proof limits and remaining M3 work.

The job has read-only repository permissions. On success or failure it retains
platform/build/test logs and crypto/QUIC results for seven days. The upload explicitly
selects diagnostic files; generated TLS private keys are excluded.

## Verification status

[Linux run 38512012802](https://github.com/jacogr/ragnarok/actions/runs/38512012802) passed on 2026-10-14
at commit `dd90bb6c56e150d896910594e7bc83474ec678f4`. Ubuntu 24.04 x86-64
completed toolchain setup, formatting, the full codec suite, a fresh QUIC build
and the authenticated cross-language QUIC proof. Diagnostic upload also passed.
This establishes the initial Linux reproducibility target for M0; M3 remains
open for IPv6, independent-peer interoperability and sustained operation tests.

The first run failed before compilation because the official Linux Odin version
string differed from Homebrew. The corrected check pins its exact reported
version and executable checksum. The current actions all use Node 24.

Pushes and pull requests run the checks automatically. Manual runs are available
under **Actions → Linux checks → Run workflow** on the default branch.

The first soak run, [38516397033](https://github.com/jacogr/ragnarok/actions/runs/38516397033),
passed its first session but stalled on the next readiness marker. A Linux socket
buffer warning separated two lines the harness expected to be adjacent. The
harness now counts exact readiness lines per session, with regression checks
for interleaved diagnostics. Full Linux soak verification awaits the rerun.

[Run 38517282183](https://github.com/jacogr/ragnarok/actions/runs/38517282183)
subsequently completed the Nim/Nim soak, then exposed an Odin linked-receive
timeout panic. Odin now uses explicit receive cancellation and a native
idle/ready cancellation regression test. The complete Linux soak remains
pending verification of this change.

[Run 38518614775](https://github.com/jacogr/ragnarok/actions/runs/38518614775)
failed at dispatcher acquisition in the cancellation selftest, without exposing
the returned error. The selftest and Odin soak now reuse one process-lived
dispatcher. Setup failures preserve their error, and platform diagnostics include
resource limits. Full Linux verification still awaits the rerun.

The [explicit-adapter migration](quic-adapters.md) adds Nim's standard-selector
I/O selftest alongside Odin's cancellation selftest. The workflow commands are
unchanged; the maintainer has reported passing Linux CI for this adapter revision.

The persistent-service step now follows the lifecycle soak, reusing the freshly built native
binaries. It retains one listener engine per language across sixteen mixed-language multi-peer
waves, with fully retired idle resource observations and final application/I/O cleanup checks.
See [the workload](quic-service.md). Its JSON and logs are included in the diagnostic upload;
verification on Linux awaits the pushed run for this increment.

The [integrated slice](integration.md) now follows the persistent-service step. It recompiles the
integrated native peers against the already verified crypto/QUIC libraries, then runs composition
fuzzing and the bounded multi-peer owned-codec/hash workload. Only explicit build/results/resource
and peer logs are uploaded from `build/integration`; fixtures and TLS private keys are excluded.
Linux verification for this increment awaits its pushed run.

The [optimized checked comparison](benchmark.md) follows correctness checks. Both candidates run
sequentially on the same allowed Linux CPU, with identical corpora/iteration counts and separate
allocation instrumentation. Results, build flags, hardware/binary/source hashes and raw logs are
uploaded. Speed has no CI pass/fail threshold; invalid outputs or unbalanced ownership fail the
measurement. The new Linux measurement awaits its pushed run.

The [persistent IPv6 peer proof](quic-mesh.md) follows the inbound service step, reusing the same
freshly built native peers. It checks all four language pairings, fallback dialing, duplicate
retirement, bidirectional CE exchanges and idle lifecycle resources. Only explicit summary, log
and resource paths under `build/quic/mesh` are added to uploads. Linux verification of this new step
awaits a pushed run. The maintainer has confirmed that the preceding benchmark CI fix passes.
