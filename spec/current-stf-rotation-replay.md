# Complete host-history checkpoint and authenticated trace continuation

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, the selected
host/lifecycle feature contracts and the complete current RawState/TraceStep wire
contract. Checkpoint envelopes remain local storage, a separate boundary.

Seven explicitly selected whole histories cover privileges, creation, code
readiness, restored preimages, held transfers, recreated supervisor authority and
repeated offender-filtered epochs. Every source transition/refusal, full parameter
tuple and logical namespace declaration is retained. Independent expected roots
bind checkpoint restores; complete pre/block/post maps drive authenticated trace
imports without constructing a successor from advertised post-state.

The source histories derive once per process in a private cache. Each caller
receives independently owned complete copies; changing one caller's maps or
steps cannot alter later expected answers. Native output never populates this
cache.

Each checkpoint successor rejects an incorrect root and a restrictive entry
limit before restoring the exact actual map. Each trace transition rejects a
recommitted wrong pre-map, wrong post-map and damaged seal before authenticating
the genuine signed block. Refused attempts preserve the selected parent and
successful installs retain its immutable snapshot. Actual current candidate
execution computes every compared successor.

Completion requires both checked native corpora, independent complete-source/root/
framing invariants, source inventory and appropriate pinned formatting. Local
macOS/Linux evidence and exact-head CI remain distinct. The explicit finite
selection does not establish arbitrary histories or full JAM/client/network/
finality conformance; M1 framing retains its separate bound.

Observed: all85 checkpoint continuations and85 authenticated trace imports pass
checked ARC/Clang on macOS and Linux, including170 checkpoint refusals,255 trace
wrong-map/seal refusals and eight original refusals per transport. Both outputs
match across8,208 frozen source/native inputs. All four independent tests and
source inventory pass; unchanged Nim/Rust sources reuse pinned formatting.
Linux restart image `ragnarok:db5-rotation-restart` is `sha256:f5232f6edb39fe7a55d429856e687578e8662d64adbab256757126ce111e25c6`; trace image
`ragnarok:db5-rotation-trace` is `sha256:7ccc23ebdf6fd77021596aa3e8a8ec2649d18fa885c70f26981a3c9ce8986623`. The preceding history PR's exact
published head passed Compile/Smoke.
