# Requested preimage announcements and acquisition

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE142/143 and GP
`3861aed15d7d016a3a416e14e61fc67dddf6daec` requested-preimage namespace/admission.

CE142 is one E4 ServiceID(E4)/Hash(32)/Length(E4) request then FIN, followed by bare FIN
(no empty E4 acknowledgment). Only an authenticated validator recipient admits it. Reuse the
existing exact on-chain outstanding request query, including account/history/length validation;
never interpret missing metadata as an outstanding request. Canonical possession suppresses a
redundant fetch. No native callback touches canonical state or verifies a blob hash.

Bound automatic followup by eight fixed intents and one active transfer, preserving public
checked-request capacity and the existing single CPU proof slot. Fetch CE143 only on the same
live announced peer generation; never reopen it after closure. Verify exact advertised length
and full content hash before retaining bytes. Native and host deadlines, deduplication, worker
fairness, stale tickets and joined close must preserve exact graph/worker ownership.

Retained preimages form a separate bounded content cache and may answer CE143 during a foreign
canonical lease. They never become complete canonical state or GP extrinsic admission. A local
publisher can announce a checked retained blob only after its own on-chain request/recipient
checks. Keep the connection owned normally after acknowledgment, allowing followup time.

Completion witnesses: exact zero-message acknowledgment/FIN, requested/unknown/malformed and
reserved-length checks; validator-role refusal; actual TLS announcement -> CE143 -> checked cache,
empty blobs, corruption/length/peer-close failures, cache-only service, duplicate/load limits,
foreign worker isolation and joined shutdown. Validator grid possession gossip is the next layer;
this layer must not claim complete CE142 gossip or complete validator operation.

Implementation ownership:

- `PreimageAnnouncement` contains only fixed decoded service/hash/length facts. Current GP
  lengths are below2^32−2; the local retrieval ceiling is8MiB minus the E4 prefix. Empty blobs
  are valid. The canonical worker uses the existing account and exact request-history query;
  successful parsing alone never creates an outstanding request.
- `PreimageFollowups` owns eight fixed intents, one active network transfer/verification and
  exact generation-bound tickets. Its noncopyable lifetime is subordinate to ApplicationNode
  and the borrowed stable Services address. It shares the existing single worker fairly with
  inbound responders and public checked operations; public checked capacity remains independent.
  Temporary transport/CPU pressure retains bounded intent until the original120s deadline.
  Source closure drops queued intent and never causes a redial. Cancelled verification retains
  its lease until exact collection/join. Foreign tickets never authorize shutdown of a worker.
- `PreimageCache` accepts only sealed complete Preimage-kind verification results. Count is8,
  total retained logical framed bytes32MiB, each entry at most8MiB including E4. Checked LRU
  ages never wrap. Mutable input/output copies cannot mutate frozen content. Allocation capacity
  and bounded transient framing/copy buffers are outside this logical retained-byte total.
- `announcePreimage` requires a live authenticated validator recipient and the publisher's exact
  outstanding canonical service request. It retains the checked blob to answer CE143 and uses
  ordinary checked acquisition for the bare-FIN acknowledgment. Acknowledgment proves neither
  peer state nor blob adoption. The normal transport remains alive for followup; explicit operator
  shutdown or connection loss may end it. No canonical preimage adoption is manufactured.
- Detached Report/Preimage service alternates cached kinds during a foreign graph lease; a
  cache miss revokes its claim without extending the original native inactivity deadline.
  Canonical CE143 search also caps cumulative candidate blob hashing at32MiB per request,
  avoiding service-count times maximum-blob work through truncated-key collisions.

Linux CI status must match the published head; this feature does not authorize heavy CI labels
or assert full JAMNP-S completion.

Observed verification for this layer:

- `make unit SUITE=jamnp_preimage_announcements` passed with independent literal TLS transcripts:
  actual requested announcement/followup, empty blob, wrong full hash, wrong advertised length,
  non-validator recipient refusal, duplicate suppression and detached CE143 service during a
  foreign Done lease. Account absence, supplied and malformed histories, existing possession,
  exact zero-message acknowledgment, reserved lengths and both cache capacities have witnesses.
- A non-validator publisher targeting an authenticated validator retains checked bytes for CE143,
  refuses an unrequested service, waits for actual FIN, and rejects a fabricated E4 acknowledgment.
  Queue saturation, deduplication and a transmitted QUIC source close demonstrate bounded intent
  and no reconnection. Private completed verification close joins its own worker; a stale ticket
  preserves a replacement foreign Done lease and its exact collection authority.
- One thousand isolated checked-cache insert/find/clear cycles retained equal occupied ARC memory
  (164032 bytes before/after in the final scoped run). Actual lowering rejected duplicate ownership
  of both `PreimageFollowups` and its containing `ApplicationNode`.

The affected `jamnp_read_client`, `jamnp_node_service` and `jamnp_report_cache` suites,
`make format-check` and `make build` also passed. Existing read-client literal dispatch was
updated for CE142; the corresponding missing CE136 consumer was corrected on its owning
report-retrieval layer before native restacking. No test runner or dependency pin changed.
