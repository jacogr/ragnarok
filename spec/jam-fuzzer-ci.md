# JAM fuzzer interface in the Fuzz group

The opt-in `Fuzz / JAM` matrix entry runs
`make check-jam-fuzzer-interface`. It validates the native implementation of the
pinned jam-conformance/jam-fuzzing fuzz-v1 interface at
`3a488be18fe7b94aa1d35bd0d6f8981ec5bbefae` against GP
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. The fuzzer schema and minifuzz script retain their prior bytes; published GP0.8.0
examples are qualified separately by the wire corpus.

The standalone command provisions its own native dependencies through Make, then
selects the source-owned `jam_fuzzer_` corpus declarations and the registered
real-entry socket workload. Corpora run sequentially with checked ARC/LTO builds.
Independent mathematical references calculate all signed blocks and complete-map
answers before native execution. The socket workload covers strict startup,
negotiation, nonempty reporting, forks, local missing-evidence closure, recoverable
consensus refusal, complete queries, reconnect isolation and SIGTERM cleanup.

Every declared corpus and the socket workload must pass. Missing/failed cases,
prerequisite errors and partial runs produce a fresh failed report and nonzero
exit status. Logs, results and a human-readable summary are retained even on
failure. Existing PVM campaign execution retains its separate matrix command and
artifacts; `fuzz-pvm` dispatch selects only that PVM family. The Fuzz aggregate
requires all selected matrix children.

This entry verifies the engine interface with fixed independently authored STF
cases. It generates no replacement random campaign and claims no live generated
campaign pass. A compatible GP0.8 polkajam-fuzz engine remains unavailable, and
both results and summary explicitly retain that pending validation. Engine
availability and an agreed matching profile can later enable known upstream
campaign execution without weakening GP checks or changing the wire protocol.

Native corpus success requires successful build and execution records together
with equal valid SHA-256 values for the observed and independently expected
transcript. A success flag alone, missing stage record or mismatched transcript
cannot satisfy the aggregate. Real-entry guest success additionally compares
observed import/session/sibling/query/rejection counters against the independently
prepared socket plan and requires fresh-session isolation. Partial loops or
missing guest evidence fail the same group even if the outer workload flag is
present. Summaries retain explicit guest import/query evidence and the pending
live-engine campaign status.

The separate **Fuzz / JAM Network** matrix entry owns the experimental issue215
`fuzz` preset through `make check-jam-network`. Its native and packaged-entry
socket readiness evidence does not change this interface group's case plan or
the pending live generated campaign status. See [network fuzz](jam-network-fuzz.md)
and [usage](../docs/jam-network-fuzz.md).
