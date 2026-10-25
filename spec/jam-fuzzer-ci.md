# JAM fuzzer interface in the Fuzz group

The opt-in `Fuzz / JAM interface` matrix entry runs
`make check-jam-fuzzer-interface`. It validates the native implementation of the
pinned davxy/jam-conformance fuzz-v1 interface at
`acd4b2da310ff25226c4d41b918712578483fd2c` against GP
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. Pins and upstream fixtures are unchanged.

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
