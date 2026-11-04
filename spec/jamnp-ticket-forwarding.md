# Timed proxy ticket forwarding

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE132 proxy broadcast;
Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7` Safrole lottery and finalized inclusion.

Only a complete checked CE131 proxy proof can create forwarding intent. Retained CE132 input
never rebroadcasts. The local authenticated identity must still be that proof's selected proxy.
Select the entire finalized current roster, including validators outside the announcement grid.
Skip the local recipient and vacant identities. A transport acknowledgment confers no state authority.

Record the local slot when initial connectivity is installed and when its accepted epoch actually
changes. Same-epoch best/finality updates must not restart that clock. Forwarding starts at this
application slot plus max(E/20,1), and recipients are evenly scheduled through the first half of
that epoch's Safrole lottery period. A missed/expired window must not restart in a later epoch.
Recheck finalized source context and inclusion before dispatch; stop retained work when included.

Bound proof intents by twice the actual pending population (maximum2046), active network requests
by16 within the existing global/per-peer quotas, and selection work by32 recipient checks per turn.
Quota pressure consumes no attempt. A failed exchange can retry at most three times within the
same forwarding window; shutdown cancels only the exact requests owned by this scheduler.
Canonical source aliases retire before another shared CPU job is admitted. No proof generation or
canonical C4 mutation belongs to this layer; local ticket production follows separately.

Completion witnesses: actual TLS proxy ingress followed by CE132 to both grid and non-grid current
validators, delay/spacing boundaries, no rebroadcast of CE132, finalized-inclusion/context/window
retirement, duplicate intent, native quota/failure bounds, exact close and ARC ownership.

Local implementation evidence:

- Real RingVRF proxy ingress and three TLS endpoints verify delay/spacing against the literal
  CE132 selector/E4/789-byte packet. The current roster includes B on A's grid and C outside it;
  the fixture checks the actual pinned grid, including cross-epoch ordinal links. Both receive
  only at their independently calculated slots. CE132 input produces no forwarding intent.
- A four-zero-byte invalid acknowledgment exhausts exactly three exchanges for B while C
  still receives its ordinary successful delivery. Repeated polls do not reopen completed work.
- Finalized inclusion removes intent and prevents offering an old completed proof again.
  Independent copied inclusion IDs share no ARC owner with the proof worker. Changed context,
  the half-lottery deadline and an unusably late connectivity application retire/refuse work.
- Closing with a deliberately withheld peer FIN cancels the scheduler's native request while
  preserving an unrelated Done Services job for exact collection. The forwarding owner and
  enclosing ApplicationNode reject actual compiler lowering copies.
- One thousand independent scheduler lifecycles preserve occupied ARC memory (924144 bytes
  before and after in the local test configuration). This measures release, not peak capacity.

Local production remains separate: this layer forwards only genuinely checked proxy ingress;
operator Bandersnatch key ownership and CE131 generation are not implied by a transport TLS key.
