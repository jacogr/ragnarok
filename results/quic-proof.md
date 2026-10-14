# JAMNP-S QUIC proof — 2026-10-14

**Both Nim and Odin now run authenticated QUIC and concurrent CE 143 preimage
exchanges on this Mac.** Nim uses ARC and the maintained Chronos/LSQUIC wrapper;
Odin uses LSQUIC through a narrow C adapter and one core:nbio event loop.
Both use the same pinned LSQUIC fork and BoringSSL source revisions.

This establishes a working local transport route for both candidates. It does
**not** complete M3: IPv6, independent-peer interoperability, sustained load,
backpressure and allocation/leak measurements remain unverified.

## Linux CI follow-up

On 2026-10-14, [GitHub Actions run 38512012802](https://github.com/jacogr/ragnarok/actions/runs/38512012802)
at commit `dd90bb6c56e150d896910594e7bc83474ec678f4` passed a fresh native
QUIC build and the full proof on Ubuntu 24.04 x86-64, alongside formatting and
codec conformance. This extends the initial IPv4 proof to Linux; the remaining
M3 tests below are still open. See [Linux CI](../docs/ci-linux.md) for toolchains
and reproducible commands.

## Executed results

Apple Silicon arm64/macOS; Nim **2.2.12 with ARC**;
Odin **dev-2026-10:84bc3fc21**; existing native compilers and CMake.
Research/networking target remains JAMNP-S commit
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, ALPN version **1**.
Full source revisions and local patches are in
[quic-proof-pins.json](../spec/quic-proof-pins.json).
No compiler or codec/spec/vector pin changed.

Executed from Ragnarok:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_quic.py --fetch
python3 interoperability/test_quic.py
python3 interoperability/test_quic.py --skip-build
python3 interoperability/test_codec.py
```

The first command with `--fetch` reproduced the native build from downloaded
pinned sources. Subsequent builds exercised the reviewed ARC patch and native
fuzz entry points. The final `--skip-build` matrix adds the separate
certificate-signature case using those same native binaries.

Final observations:

```text
Formatting check passed (58 source files).
Nim QUIC selftest: 10000 malformed DER/header cases passed
Odin QUIC selftest: 10000 malformed DER/frame cases passed
PASS QUIC: 64 peer pairs; 4 valid x 8 concurrent CE 143 requests; 36 TLS/identity rejections; 24 authenticated protocol rejections
```

All previous codec suites pass unchanged: natural, fixed-unsigned, bounded,
composite and full work-digest checks, including their official fixtures and
negative compilation tests. No networking dependency is imported into the codec.

| Acceptor | Initiator | Valid result |
| --- | --- | --- |
| Nim | Nim | Authenticated, eight CE exchanges, both FIN directions |
| Odin | Odin | Authenticated, eight CE exchanges, both FIN directions |
| Nim | Odin | Authenticated, eight CE exchanges, both FIN directions |
| Odin | Nim | Authenticated, eight CE exchanges, both FIN directions |

Nine TLS/identity rejection scenarios are run in every pairing: wrong client
SAN, absent SAN, multiple SANs, ECDSA key, **Ed25519 key with an ECDSA-signed
certificate**, missing client certificate, wrong server SAN, wrong expected
server key and wrong chain ALPN. A successful client-side TLS notification
alone is not treated as peer-pair/application success: both sides must complete
all exchanges for a valid case.

Six authenticated protocol rejection scenarios are run in every pairing:
wrong stream kind, uint32-max claimed message length, unknown preimage hash,
truncated hash followed by FIN, trailing message content and absent request FIN.
The suite asserts that these cases first authenticate, so failures really reach
the application parser. No failure is accepted as an empty or fabricated response.

While eight requests deliberately waited for missing FIN, OS thread snapshots
showed **one thread per process** in all four pairings. This supports the event-loop
approach for this experiment; it is not a connection-scale/sustained-load result.
The evidence is retained in `build/quic/results.json` and per-case logs.

## What the proof implements

TLS 1.3 authenticates two independently generated Ed25519 test identities.
Native Nim/Odin policy checks the certificate key algorithm, certificate
signature algorithm, one DNS SAN, exact key-derived SAN bytes, and the expected
server public key when dialing. Acceptors can discover a previously unknown
key with consistent certificate/SAN; validator membership is subsequent policy.
The public-PKI chain/self-signature is not the trust anchor, while TLS still
proves possession of the private key through its handshake.

The SAN formula follows the **literal pinned document**, including its `$e`
prefix and unusual alphabet, least-significant groups first. This is not standard
RFC base32. An independent Python arbitrary-precision formula generates fixture
names. Compatibility with an independent JAM peer remains to be established;
the earlier version-0 mirror discrepancy has not been hidden by changing ALPN.

CE 143 sends kind byte 143, an E4 byte length and a 32-byte hash request,
followed by request FIN. The fixture map returns preimage bytes `01 02 03`,
framed by their E4 length, followed by response FIN. There is no extra natural
blob-length prefix inside this single-sequence network message. The fixture
hash is Blake2b-256 of those bytes. Nim deliberately splits request writes to
exercise partial/coalesced stream reads. All eight requests start before replies
are awaited. Requests and responses are validated before success is reported.

Nim allocates only bounded application message buffers after validating frame
lengths. Odin uses fixed owned stream/packet buffers and preserves pending-write
state across would-block/partial writes. UDP sends borrow C packet bytes only
until a synchronous nonblocking send returns. Receive/timer callbacks drain
before native context destruction. Deadlines bound missing FIN and cancellation;
this is not yet a full flow-control/backpressure campaign.

The C adapter handles LSQUIC/TLS ABI layouts and primitive X.509 extraction.
It contains no JAM SAN formula, identity acceptance, message framing, codec,
preimage map or protocol parser. Those are native Nim/Odin implementations.

## Dependency findings and fixes

Dependencies live under ignored `build/quic/`, with **no global nimble install**
and no upstream package-install hooks. The runner fetches exact committed
sources/submodules, invokes reviewed native builds and keeps the build log.
Generated fixture private keys remain in ignored temporary build storage.
Python **3.12+**, CMake, clang/clang++, OpenSSL with Ed25519 support and the
pinned language compilers are required. The local run used Python 3.14.
BoringSSL assembly is disabled in both builds; these results are correctness
checks, not representative optimized performance measurements.

Two local dependency patches are required for this proof:

1. Chronos: four address helpers now explicitly convert failed results to their
   declared `TransportOsError`; Nim 2.2.12 otherwise inferred an unlisted
   `OSError` through the generic result helper. No network error was suppressed.
2. nim-lsquic: stream scheduler closures capture only a retained transport
   context through a non-async factory. The original async-frame capture
   produced a self-retaining stream cycle under ARC; that warning disappears.

Patch files are committed and the runner applies exact reviewed transformations
idempotently. They need upstream review or long-term maintenance if this stack
is selected. A connection close-closure cycle warning remains; inspected client
and server close callbacks explicitly clear it before releasing their native
pin. Successful/rejected shutdown paths ran, but sustained allocation/leak
measurements are still necessary to prove that all ownership paths are sound.

The rejection campaign also caught an early-free expected-key buffer and a
repeated EOF loop on partial headers in the Odin proof. The corrected buffer
lifetime spans TLS callbacks; incomplete header FIN now rejects immediately.
Native fuzz properties and real truncated-request cases cover the latter.

## Practical conclusion and next gate

Odin has a workable nonblocking route; lacking async/await syntax is not a QUIC
blocker. Nim supplies a shorter awaitable integration but currently carries
compatibility and ARC ownership patch obligations. These observations do not
select a winner.

This is a bounded **IPv4 loopback proof with one connection per process**,
eight CE streams and a fixture map. Peers terminate an attempted session after
an application failure; continued service to other streams after one malformed
request is not established. Production UP stream replacement, builder ALPN
negotiation, resumption/early-data policy and validator connectivity are absent.

Before calling M3 passed, run IPv6 and an independent pinned JAMNP-S peer;
exercise slow readers and actual flow-control pressure, reset/cancellation during
pending writes, many connections, repeated in-process reconnect/teardown and
allocation/latency/thread measurements. Keep application queues explicitly
bounded and verify unaffected streams survive individual request failures.

The initial authenticated transport/exchange proof is complete. Wait for the
maintainer's next bounded networking increment before expanding the prototype.
