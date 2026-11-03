# JAMNP-S compliance work

## Scope and authority

The implementation target is the complete JAMNP-S `simple.md` at
[`aa0e2b8498c0b1bc1725af2903704d701c6577ab`](https://github.com/zdave-parity/jam-np/tree/aa0e2b8498c0b1bc1725af2903704d701c6577ab),
qualified by networking-pin PR #1834 and recorded by the current vendor gitlink.
The current audit implementation starts from master `51a43ab9`; these feature layers do not
change dependency pins. Audit behavior uses the upgraded schemas, not the legacy forms. The pinned Gray Paper supplies the embedded JAM structures, signing
domains, audit selection and state authentication; JAMNP-S supplies transport behavior.

The maintainer requested full compatibility, including the missing audit streams. This record
tracks that target; a checked codec or successful development exchange alone is insufficient.
Every completed row requires a production route, validated state/role inputs, bounded lifecycle
handling, malformed/negative tests and independently checked wire evidence. Until those checks
are supplied, the row remains incomplete.

## Source boundary

`src/jamnp-s/` owns peer identities, JAM message framing, stream state, retained sessions,
announcement handling, CE128 downloads and CE143 development integration. `src/quic/` retains
only nonblocking UDP readiness and the native QUIC/TLS transport adapter, including primitive
certificate extraction. The relocation uses `git mv`; module basenames and aliases remain
unchanged. Files inside `src/pvm/` are not moved or renamed.

## Requirement inventory

The paths below describe the existing implementation after relocation. “Partial” means some
production path exists; it does not assert all normative behavior has been verified.

| Pinned section | Existing implementation | Required completion evidence |
| --- | --- | --- |
| Encryption, alternative name | `protocol.nim` validates Ed25519 certificate observations and the literal key-derived SAN; transport supplies mutual TLS | Live incoming/outgoing rejection matrix, exact single SAN, optional discovered peer and pinned outgoing identities |
| ALPN | `alpn.nim` validates identifiers; ordinary commands bind to captured configured genesis and acceptors negotiate both base and `/builder`, with real TLS coverage | CE133 admission and builder capacity independent of suffix |
| Required connectivity | Complete addressed transport/configuration; `topology.nim`, `admission.nim` and `connections.nim` provide full-state roster facts, reserved admission, gated epoch policy and actual preferred/fallback connection ownership | Ordinary node command/backend wiring, authoritative finality feed and UP0 grid stream lifecycle |
| Epoch transitions | `admission.advance` and the connection owner preserve old connectivity until explicit finalized-epoch and elapsed-slot gates pass | Ordinary-node finality publication and command integration |
| UP/CE lifecycle | Per-stream bounded owners, cancellation and retirement; actual-ID UP admission and same-connection greatest-ID replacement | General CE transcripts/dispatch, both FINs before success, rejection/cancellation mapping across all kinds |
| E4 messages | Shared bounded `messages.nim` codec, CE143 frame inspector, UP0 incremental reader, CE128 receivers | Shared bounded multi-message parsing with exact message extents and protocol-specific transcript/FIN rules |
| Grid | No general validator gossip scheduler | Pinned grid neighbors and forwarding with duplicate suppression |
| UP0 block announcement | `announcements.nim`, `announcement_stream.nim`, current sync and Tiny routes | Complete handshake/announcement rules, greatest-ID handling, finality/leaves validation and actual peer exchanges |
| CE128 block request | `block_service.nim` canonical two-direction responder and real TLS reset/FIN tests; existing download clients/devnet | Ordinary Services integration, canonical read scheduling and bounded per-peer admission remain; see [contract](jamnp-block-service.md) |
| CE129 state request | Canonical `canonical_read.nim` backend and shared native stream route with authenticated boundary/TLS tests | Ordinary Services worker scheduling and per-peer/global admission remain; see [contract](jamnp-canonical-read.md) |
| CE131/132 Safrole tickets | No runtime route; existing state ticket admission is separate | Target epoch, attempt/proof validation, next-set proxy selection from output tail, uncertainty rejection and timed forwarding |
| CE133 work-package submission | No runtime handler | Core/package bound before authorization, exact extrinsic lengths, normal and builder ALPN acceptance, import recovery |
| CE146 bundle submission | No runtime handler | Core/mappings, bounded authorized package before bulk data, extrinsics/segments/import proofs and exact transcript |
| CE134 work-package sharing | No runtime handler | Core/shard count/mappings, acceptable anchor-window count, authorization/refinement and returned report hash/signature |
| CE135 work-report distribution | No runtime route | Guaranteed report decoding/credentials, slot admissibility, current/next validator delivery and third-guarantor grace |
| CE136 work-report request | No runtime handler | Exact requested report hash, authenticated report response and preferred negative-judgment sources |
| Shard assignment, CE137 | No runtime route | Deterministic assignment, bundle/segment shards and erasure-root justifications; validated storage before acknowledgment |
| CE138 audit shard request | No runtime handler | Request root/index, bundle shard plus tagged co-path, response authentication, nonvalidator requests and bounded throttling |
| CE147 bundle request | No runtime handler | Root-bound bundle service and validation, fall back to CE138 on invalid/unavailable bundle |
| CE139/140 segment shards | No runtime handler | Grouped roots/indices, at most 6144 requested shards, exact segment-shard widths, per-shard proofs for140 and verified retry/fallback |
| CE148 segment request | No runtime handler | At most3072 segments, segment/proof sequences, root-bound verification and CE139/140 fallback |
| CE141 assurances | No runtime route | Anchor/bitfield/signature, validator-role authentication, epoch-sensitive recipient sets and slot timing |
| CE142 preimage announcement | No runtime route | Service/hash/length, on-chain request lookup, CE143 followup, possession-based grid gossip and connection lifetime |
| CE143 preimage request | `canonical_read.nim` canonical service-state lookup, full-hash refusal and real TLS transcript | Ordinary Services routing and CE142 reception/cache remain; development workload stays isolated |
| CE144 audit announcement | `audits.nim` structural batch codec; no runtime handler | Batched header/validator/intent/96-byte proof, authenticated initial/later intent, derived cores/tranche, duplicate intent suppression; no announcement for negative-judgment-triggered audits |
| CE145 judgments | `audits.nim` structural batch codec; no runtime handler | Batched epoch/validator/validity/report/signature, inline invalid guarantee before hash/signature,2/3 distinct guarantors, authenticated judgment gossip, report retrieval and audit triggers |

## Planned review units and acceptance

1. Separate protocol modules from transport without changing behavior. Verify the resolved
   import graph, all production semantic checks, affected ownership/result guards and representative
   native networking/download consumers. Publish this coherent refactor before changing behavior.
2. Supply shared bounded stream/message machinery and the upgraded audit codecs, with exact
   independently constructed bytes, every-prefix/trailing/overflow tests and compiler-enforced
   result/ownership boundaries. Codec completion alone does not close the corresponding runtime rows.
3. Connect audit shard/bundle/report service and authenticated audit announcements/judgments to
   actual application state and the nonblocking peer dispatcher. Verify proof rejection, concurrent
   healthy siblings, cancellation, FIN, bounded queues, stale epochs and teardown.
4. Complete the remaining request/distribution protocols and validator connectivity/gossip timing
   against authenticated state. Exercise interoperable exchanges for every stream kind, both normal
   node and validator roles, including fallbacks and invalid peer behavior.

Supporting fixtures must bind the exact specification revision and compare against independent
wire expectations. Final compatibility requires every inventory row to be supported by retained
runtime evidence; unresolved normative ambiguities must be documented with focused witnesses.

The shared framing and audit codec contracts are recorded in [message codecs](jamnp-messages.md).
Their tests establish structural behavior only; runtime/authentication requirements remain open.

[Persistent stream lifecycle](jamnp-stream-lifecycle.md) records actual-ID UP0 replacement,
claim revocation, pending-route handling and connection isolation.
