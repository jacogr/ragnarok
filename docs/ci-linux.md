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

After setup, the job runs:

```sh
python3 tools/format.py --check
python3 interoperability/test_codec.py
python3 interoperability/test_quic.py --fetch
```

The codec command covers both native implementations, negative compilation
fixtures, official vectors and shared conformance cases. The QUIC command fetches
pinned dependencies, builds them from scratch, and runs the authenticated
cross-language CE 143 proof and rejection cases. Dependencies are not cached.
Python 3.12 supports the safe archive extraction used during setup.

Odin's Linux `core:nbio` backend uses io_uring. The workflow enables it through
optional kernel policy settings on this temporary runner before testing.
See [the QUIC proof instructions](quic-proof.md) for native dependencies,
protocol pins, proof limits and remaining M3 work.

The job has read-only repository permissions. On success or failure it retains
platform/build/test logs and QUIC results for seven days. The upload explicitly
selects diagnostic files; generated TLS private keys are excluded.

## Verification status

The workflow passes actionlint validation. Download checksums, archive layout,
formatter patch application and the Linux Odin identity check were verified
locally. Formatting and the full codec and QUIC regression checks passed on
macOS; this does not demonstrate Linux execution.

The [first Linux run](https://github.com/jacogr/ragnarok/actions/runs/38511417305)
passed toolchain setup and formatting, then failed the Odin version check before
compilation. Its actual version string is now pinned alongside the verified
executable checksum. Push this fix to run the suite again, or use **Actions →
Linux checks → Run workflow** after it reaches the default branch. Linux
reproducibility remains pending until the complete run succeeds; M3 remains open.
