# Native JAM fuzzer-v1 wire boundary

Authority is the unchanged pinned davxy/jam-conformance commit
acd4b2da310ff25226c4d41b918712578483fd2c, specifically
fuzz-proto/fuzz-v1.asn and fuzz-proto/README.md. The Gray Paper remains the JAM
protocol authority; the tooling pin does not establish exact GP compatibility.

The native state/fuzz_protocol module owns all seven published discriminants:
PeerInfo, Initialize, StateRoot, ImportBlock, GetState, State and Error.
Peer identity contains E1 fuzzer version, E4 feature bits, three-byte JAM/app
versions and a compact UTF-8 name. Versions and unknown feature bits are
preserved as declarations; negotiation and compatibility are session decisions.

Initialize composes a schema-bound Header, compact KeyValue sequence and at
most24 ancestry entries of E4 slot plus32-byte header identity. State has the
same KeyValue sequence with no advertised root. Complete records are scanned
before input-derived allocation, then captured through the ordinary complete
StateStore with an independently recomputed opaque root. Duplicate keys,
noncanonical counts, malformed/truncated extents and resource overruns refuse
ownership. Opaque capture never supplies raw logical identities or chain trust.
ImportBlock uses the existing current structural block codec; it runs no STF.

Private immutable acyclic owners retain complete original wire and validated
children. Getters reject default owners and wrong message kinds. State/map,
header and block children retain their own immutable ownership; ancestry and
wire output are detached copies. Every failed result contains its reason only.
Outgoing PeerInfo, StateRoot, State and Error constructors preserve exact byte
budgets. State export uses deterministic complete-map key order. Error encoding
provides no license to classify internal failures as consensus import errors.

Transport helpers validate one E4 payload length before allocation and encode
one complete message with that exact prefix. Empty/oversized lengths, malformed
prefix extents and source/output-limit refusals never grant a successful frame.
A socket server, session transitions and authenticated block import are later
layers; this module opens no listeners and installs no chain state.

The source-owned corpus uses all878 exact binary/JSON messages from the pinned
known examples, retaining every source SHA-256. Independent current-profile
header/block references select581 structural successes and297 typed refusals:
five historical Initialize headers and292 historical blocks. The accepted
State witness also compares the entire independent canonical checkpoint and
recomputed root, not just message kind. All seven discriminants have upstream
witnesses. The published deliberately faulty example remains an intentionally
faulty historical session, not a golden STF chain.

These numbers describe codec outcomes. They are not passes of the GP0.7.0/
0.7.2 sessions or a GP0.8 fuzz campaign. Native unit witnesses separately cover
valid current-profile Header/Block composition, all kinds, absent/wrong-kind
owners, zero and nonempty ancestry, immutable copies, compact/UTF-8 failures,
duplicate keys and exact frame/output boundaries. Private-field guards, pinned
formatter idempotence, source-owned registry/inventory and maintained native
execution cover the codec layer. The known upstream fuzzer remains the planned
campaign driver; no replacement campaign generator is introduced.
