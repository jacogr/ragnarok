# QUIC peer startup CI investigation

2026-10-15. Reported [GitHub Actions run](https://github.com/jacogr/ragnarok/actions/runs/38720815259),
job 116374611699, failed in `Build and verify Linux QUIC` while waiting for the
`nim / nim / multi-san` server to announce readiness. Native builds and parser/I/O selftests had
passed. The supplied assertion did not distinguish process exit from its three-second deadline.

The exact failed server output could not be retrieved: GitHub's public API exposes job/artifact
metadata, but downloading the retained artifact returned HTTP 401 without authentication.
Consequently the cause of that particular server failure remains unconfirmed.

## Confirmed shared harness defect and correction

`interoperability/test_quic.py` selected a local port with Python's default TCP socket and then
launched a UDP QUIC listener on that number. TCP and UDP have separate port namespaces: that
reservation can succeed while an existing UDP socket already owns the port. The kernel regression
test reproduces this directly. Four worker threads also released reservations independently,
leaving a selection-to-bind race between suite servers.

The corrected harness reserves IPv4 loopback **UDP**, releases immediately before spawning the
server, and holds a shared startup lock until that listener reports readiness. Other matrix
workers cannot perform their server-port selection during that handoff. Exchanges continue
concurrently through the existing four-worker executor. The native child still binds its own
socket, so this is not atomic descriptor inheritance and cannot exclude every unrelated process
from the brief release-to-bind interval.

Readiness now requires an exact `READY` line from a live process. Startup failures include the
actual exit code, failure phase, log path and diagnostic output. A warning containing the word
READY cannot release a client prematurely. Failed startup still releases the lock and retires
the child. The three-second startup deadline, four-second process waits, certificate rejection,
authentication-before-framing checks, success markers and thread limits are retained.

No native implementation, dependency, compiler pin or protocol behavior changed. This is shared
infrastructure work and does not add compiler repairs or production LOC to the matched language
comparison. It does not establish a Nim decoder, TLS or multi-SAN validation defect.

## Verification

Local macOS arm64 verification using existing native peers:

- **6 new startup regression tests passed**: TCP/UDP namespace mismatch, live readiness, exact
  marker/deadline diagnostics, exited-server diagnostics, real UDP handoff/client port agreement,
  and failed-startup cleanup/lock release.
- **144 native matrix cases passed across all 9 directed language pairings**, including the
  reported Nim/Nim multi-SAN case. Native parser selftests passed 10,000 malformed DER/frame
  cases and I/O selftests passed 256 retirements in each language.
- **16 existing lifecycle harness regression tests passed**.
- `git diff --check` passed.

[Receipt and source/binary hashes](quic-startup-ci/receipt.json),
[startup unit output](quic-startup-ci/startup-tests.log),
[native matrix output](quic-startup-ci/matrix.log),
[compressed per-case results](quic-startup-ci/results.json.gz) and
[lifecycle test output](quic-startup-ci/lifecycle-tests.log) retain the observations.

Linux CI now runs the startup regression tests before building/running the native QUIC matrix.
A new remote pass remains to be observed. Reproduce locally after the pinned peers are built:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_quic_harness.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_quic_soak_harness.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_quic.py --mojo --skip-build
```
