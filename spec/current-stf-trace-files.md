# Bounded published trace files and actual STF import

The published TraceStep schema remains pinned at vectors
`23061ae1f9b51171c01387e7dde0f15794c98e24`; execution authority remains GP
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and the independently configured
actual application chain.

`state/trace_file` adds strict offline file input/output around existing trace
ownership. Reads use the existing bounded regular-file helper, which detects excess
input with one additional byte and closes the actual descriptor before returning.
Only complete EOF followed by complete three-field decoding and exact consumption
can expose an owner. A valid prefix with any trailer, or two concatenated steps,
is refused. Genuine I/O and nested codec/root failures retain their typed reasons;
refused/default alternatives expose no trace, file buffer or progress prefix.

Export preflights detached complete wire before invoking the existing atomic file
replacement helper. A refused owner or short encoding ceiling leaves an existing
target untouched. Native path/publication failures remain distinct, including a
visible-but-unsynced replacement, which never becomes a durable success receipt.
The caller retains offline scheduling and a stable directory namespace. No new
OS wrapper, transport callback I/O or chain adoption path is introduced.

Forty independently calculated chains materialize255 exact published trace files
before the native build. A private hexadecimal pathname transport preserves spaces;
it is separate from the unchanged published binary file representation. Each file
is loaded through bounded EOF, then enters actual authenticated STF import with
explicit trusted chain Parameters. Exact pre/block/post maps, logical exports,
fresh-store continuation and765 wrong-map/seal refusal observations remain those
independently derived before execution. Native execution never supplies golden
file contents or successor values.

Native file units cover empty/missing/invalid paths, nonregular input, one-short
read limits, empty/truncated/corrupt files, trailers and concatenation, exact atomic
output, existing-target preservation on encode refusal, failed publication and
retained ownership after subsequent file changes. Existing low-level file helper
lifecycle tests remain authoritative for underlying close/fsync/rename behavior.
Compiler privacy guards, independent file hashes/maps/refusals, inline trace replay
regression, semantic checks, twice-idempotent formatting and inventory complete the
scope. Local checked ARC/Clang evidence is separate from exact-head Linux CI.
Standalone operator/conformance invocation and external-client differential checks
remain next; pins, historical fixtures and STF algorithms are unchanged.
