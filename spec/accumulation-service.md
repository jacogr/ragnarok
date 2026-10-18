# Accumulation service code context

## Scope and pinned authority

`src/state/accumulation_service.nim` resolves the account and code entry gate for one prepared
initial-round service. Authority is GP 0.8.0 at revision
`07f041dabd073f9018b418e9ee72e79dd2185401`: `accounts.tex`'s service code/metadata definition
(SHA-256 `badaf09677a420ec6d47ae439f8d7641173e8fd460ed8f2305e336d999073d7a`) and
`pvm_invocations.tex`, equation `accinvocation` / `Psi_A`
(SHA-256 `67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`).
It builds on [initial round planning](accumulation-round.md) without invoking a PVM or writing state.

The account's code-hash preimage is `E(length(metadata)) || metadata || code`. Only metadata has a
length prefix; the remaining suffix is the complete code blob. There is no additional code-length
field and no alternate-envelope fallback. A malformed/truncated/noncanonical envelope supplies no
code. Valid empty code is a distinct eligible blob: program validation and its execution outcome
belong to the PVM layer, not this lookup gate.

`Psi_A`'s protocol size gate measures extracted code, excluding the metadata and its framing.
`ServiceCodeLimit` supplies that explicit chain parameter; the ordinary GP value is 4,000,000.
The bound API authenticates the source state and candidate slot, not the caller's chain constants.
There is no additional invocation-time minimum-gas, code-hash-versus-old-report or balance filter:
report admission already has its own code/minimum-gas rules, and `Psi_A` uses the actual account
code in the applicable execution state. Zero-gas, allowance-only services remain valid contexts.

## APIs, provenance and ownership

`prepareAccumulationService` accepts prepared inputs, a nominal `InvocationServiceIndex`, an
explicit complete-map state snapshot, candidate slot and resource policy. It resolves exactly that
service's C(255, service), requires the complete fixed version-zero metadata record, and looks up
its code-hash preimage through the existing preimage namespace. The preimage/hash invariant is
checked; corrupt state and cryptographic backend failures cannot masquerade as absent code.

Successful copied metadata distinguishes `Missing`, `Malformed`, `Oversized` and `Ready` code.
Unavailable alternatives carry no executable byte copy: `serviceCode` refuses extraction with
`CodeUnavailable`. Ready code, including empty code, is copied independently on extraction.
`serviceInputAt` accepts only an inner input ordinal; it cannot substitute a different service group.
Private acyclic owners retain the complete immutable source map, original prepared inputs, copied
account fields and independently captured code. Released parent handles or mutations of extracted
bytes do not change later reads. Failed/default results contain only a reason behind private tags
and selected-success contracts.

`prepareBlockAccumulationService` accepts a genuine `BlockAccumulationRound`. It derives the exact
admitted **parent** state and authenticated candidate slot through the retained queue/admission,
never from a caller-supplied replacement map or a stage's posterior snapshot. Its separate bound
owner retains both the original round and the resolved pure context.

The API prepares one service at a time, avoiding speculative batch copies of every program.
The original input projection already bounds service and input counts. `preimageBytes` independently
bounds a complete raw preimage before copying, content hashing or envelope parsing. Exceeding this
local resource ceiling is `LimitExceeded`, not successful protocol-size ineligibility. Fixed account
extent checks precede account copying. Envelope offsets and suffix lengths come from the existing
bounded canonical parser, and no unchecked length addition or narrowing is introduced.

## Deliberate execution boundary

A missing account is a typed `MissingAccount` **preparation refusal**. This module does not invent
an absent-service execution outcome, infer block invalidity, or synthesize account fields. Such
outcomes must be handled when complete accumulation execution is integrated.

Contexts containing deferred transfers are refused explicitly: transfer balance credit belongs to
a real state-transition slice. Initial rounds contain no transfers, so the bound initial-round path
is supported completely within this scope. No balances, account timestamps, storage, privilege
chapters, output logs or queues are modified. The unavailable-code statuses identify the `Psi_A`
entry gate only; this layer does not fabricate zero-used-gas execution results or checkpoint states.

## Verification

`tests/unit/state/test_accumulation_service.nim` checks 408 deterministic independently authored
metadata/code envelopes and protocol/resource limits. The Python oracle uses unbounded prefix/length
arithmetic and independently encoded compact lengths; native code uses the maintained bounded parser.
Both empty/malformed encodings and metadata lengths around 127/128 and 16,383/16,384 are covered.
Tests compare the gate status and complete code suffix, preserve zero gas with maximum account
minimums, and check that returned bytes are independent copies.

Literal cases cover missing accounts/preimages, malformed/extended/versioned account records,
preimage/hash corruption, both namespace/content hash failures, resource preflight before content
hashing, rejected transfer contexts, default handles and hostile indices. Genuinely signed blocks
bind matching report/account code identities, real assurance-derived inputs, parent C(12) and the
actual candidate slot. Extracted operands remain usable after all source contexts leave scope.
A 1,000-cycle success/refusal loop requires unchanged live ARC occupancy. Strict runtime probes
protect failed/default/unavailable extraction; compiler probes protect private storage, nominal
service ordinals and protocol code limits. Two independent Python tests anchor literal envelope
and resource-boundary examples.

The original signed-report template remains hash-pinned. These new code contexts are authored tests,
not published complete accumulation STF execution outputs; neither upstream pins nor dependency
sources change.

## Next bounded work

[Invocation bootstrap](accumulation-invocation.md) now prepares compact arguments and the
collision-checked initial service ID, with authenticated slot and posterior entropy. Complete initial
partial-state binding for regular/exceptional contexts is next; actual execution, transfer credit,
checkpoint outcomes, later rounds and publication remain separate.
