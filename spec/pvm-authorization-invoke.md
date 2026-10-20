# Bounded Is-Authorized invocation

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` isauthinvocation/isauthorizedmutator, work-package historical
authorization-code definition, Psi_M and standard initialization; vector pin
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` remains unchanged. Existing grow_heap
adoptions and other specification gates remain unchanged.

Scope: run the original owned package's authorizer, using its authorizer-host
service and lookup-slot historical preimage, verifying the declared preimage hash
before stripping canonical metadata. Missing code yields BAD/zero gas. The code
suffix, excluding metadata, above 64000 bytes yields BIG/zero gas. Present preimages
require an explicit copy/hash budget even for BIG; malformed metadata/envelopes/
programs remain typed local gates. Initialize entry zero with exactly E2(core) and
50000000 gas, after checking the core's full-width chain and E2 domains.

Dispatch only gas, grow_heap and fetch. Configure parameters and the original
package; entropy, trace, current item, external inputs and accumulation operands
are absent. All other host identifiers use the shared charged WHAT response,
including refinement-only IDs. Heap bounds derive from this initialized envelope.
Local preparation, host, engine and output policies remain independent typed
refusals with guarded stage details and no partial machine, trace or gas result.

Normalize halt through Psi_M return-buffer readability; unreadable intervals yield
successful empty output. Panic/page fault and OOG retain their work kinds and no
success bytes. Used gas is allowance minus nonnegative remaining credit, including
zero use on unaffordable initial block and exact host debt saturation. A local
output cap is a refusal, not report Oversize. The report's 49152-byte trace gate
and sequencing before refinement remain a subsequent composition layer.

Invocation-prefixed public types coexist with the existing state authorization codec.
Immutable acyclic output retains original complete state, package, parameters and
selected core/host/anchor; metadata and trace extraction are copies. No public
entry accepts replacement CPU/code/trace/result tuples. No state publication or
full/light database changes; authenticating state/freshness remains external.

Completion: authored real guests for fixed arguments/gas, code and host selection,
metadata/code-size boundaries, historical host/anchor eligibility, missing code,
fetch package/configuration/authorization/parameters and absent selections,
unknown hosts, heap growth, halt/readability, panic/fault/host and instruction OOG;
independent local budgets and guarded stage details; replay/source lifetime/copy
isolation; optimized misuse and compiler privacy/nominal/source rejections; fresh
1000-cycle ARC release. Regress historical lookup and host fetch; inventory/tooling
and pinned formatting must pass.

Local evidence: checked optimized native `pvm_authorization_invoke`,
`pvm_historical_lookup` and `pvm_fetch_context` pass with fresh 1000-cycle ARC
release, respectively 975440/975440, 56192/56192 and 16880/16880 occupied bytes.
Sixteen optimized runtime alternative/detail/owner/trace guards, six compiler
privacy/nominal/source rejections, 19 inventory/provenance Python tests, verification
inventory and pinned formatting pass. The native suite imports both the state
codec and invocation result domains to verify coexistence. These are local macOS
results; exact-head Linux CI remains independent.

Next: bind successful authorization output to ordered refinement/report construction.
Report authentication, segment-root/availability/erasure assembly and publication
remain open. M1 framing is complete; full state serialization remains open.
