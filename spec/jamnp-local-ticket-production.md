# Optional local Safrole ticket production

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE131 generating-validator
first step and CE132 self-proxy skip; authorized GP `fad0ded4a433052397bf7234352a57fe491883f7`.

A node without explicitly configured operator signing material never generates tickets. Configure
an exact 32-byte JIP-5 validator master seed locally; derive and own only its Bandersnatch key,
clearing temporary seed bytes. Its public key and actual TLS Ed25519 identity must match the same
pending-roster position. A TLS key alone cannot manufacture this signing capability. Raw key or
seed bytes never enter a network packet, log, public RPC response, or retained source snapshot.

Real signing runs on the existing exact capacity-one Services proof lease, with detached finalized
C4/C6 state and a private immutable signer capability. Explicit source certainty, current accepted
epoch, GP attempt ceiling and the pinned 0/1 domain apply. Preserve genuine native failure causes.
The shared worker's non-ticket consumers must remain independent of optional signing linkage.
Use standard public allocation/destruction only; no vendor/compiler/runtime changes.

Perform the first step after actual connectivity application plus max(E/60,1). Generate at most
attempts 0/1 for each selected signer/epoch context. Recheck finalized inclusion/context and clock
on collection and sending. CE131 goes only to the selected next-roster proxy on an authenticated
validator connection. A self-proxy skips CE131 and enters the existing checked pending/CE132 path.
Bound queued production, native requests and retries; expiry and shutdown retire only exact owned
work and never join a foreign replacement job. Canonical block inclusion remains separate.

Completion witnesses: genuine configured-key proofs, unconfigured/incorrect/unregistered keys,
attempt and epoch bounds, independent literal CE131/bare-FIN TLS transcripts, self-proxy skip,
first-step timing, stale/included results and native quota/retry/close ownership; actual copy
lowering and ARC release; affected read/forwarding/application/CLI consumers and checked build.

Operator interface: `node --node-validator-seed FILE` is optional and node-only. FILE contains
exactly 32 binary JIP-5 master-seed bytes, with no hex, text newline or alternate representation.
Startup reads at most 33 bytes and clears the whole temporary buffer on every path. The stored
resource owns only a derived Bandersnatch key; it exports no scalar, seed, native pointer or
caller-controlled signing callback. Configuration returns no key owner. Reapplying the same
public key preserves its configuration generation, completed attempts and active CE131 exchanges.
Changing configuration is refused while any shared canonical worker lease remains active or Done.

The private signer resource uses a standard allocated key box, immutable acyclic ARC lifetime,
closed production/release callbacks and an explicit move reset. Underlying resource storage
cannot copy; ordinary immutable handle aliases share only lifetime. No private runtime hook,
compiler change or dependency upgrade is required. Typed production uses the existing shared
proof worker and RPC pause/collect/join contract. The source captures independent pending BS/Ed
metadata and includes the ordered BS keys in its epoch context fingerprint. No whole canonical
map, Native stream handle or caller seed is retained by that source.

`TicketOrigins` retains at most two whole checked proofs and two exact Native requests. It
rechecks current finalized context/inclusion before dispatch, allows three exchanges per target,
and consumes no attempt on shared quota pressure. Unavailable/vacant proxies receive no invented
fallback. Self-proxies enter the existing checked pool and delayed all-current-validator forwarding
scheduler. Delivery work ends at half the lottery period; valid GP pending inputs remain until
the ordinary GP cutoff or finalized inclusion. A raw completed crypto outcome is a separate fact
from current-clock/delivery admission and confers no canonical inclusion authority.

Local witnesses:

- Genuine registered-key signing verifies against an independently captured source and ordinary
  network recipient checks. Incorrect seed width, missing/incorrect/unregistered keys, attempts,
  stale epochs and already-finalized IDs return guarded reasons with genuine child causes.
  A 24-member/E12 fixture enforces the actual GP ceiling of one network attempt.
- Actual authenticated TLS observes literal CE131/132 selectors, both E4 length octets, use epoch,
  attempt and complete 789-byte payloads before bare FIN. E120/Tail100 separates first-step slot3
  from self-proxy forwarding slot7 after connectivity application at slot1. Unconfigured/wrong
  keys send no tickets; self-proxies send no CE131.
- Idempotent configuration does not repeat generation, reset retries or cancel withheld-FIN
  delivery. Invalid acknowledgments stop after exactly three exchanges. Expiry after genuine
  Done prevents both remote delivery and self-proxy retention; joined close and a foreign
  replacement Done job preserve exact secret/CPU/Native ownership.
- 1000 fresh selected-source lifecycles release detached key/inclusion metadata. 1000 signer-owner
  lifecycles preserve occupied ARC memory (87312 bytes before/after in the complete local test).
  Actual lowering rejects copies of StateProofWorker, Services, ApplicationNode and TicketOrigins.
- Existing ticket admission/forwarding, checked requests, proof worker/Services and foreground CLI
  suites pass. The ordinary node-service consumer still passes without adding direct Bandersnatch
  linkage. Formatting and the normal checked ARC/Clang build pass locally.

This completes local production and the two-step ticket runtime. Other protocol families,
autonomous canonical synchronization/adoption and complete validator operation remain tracked
by the broader JAMNP-S implementation work.
