# Executable JAM fuzzer interface

Authority is the pinned davxy/jam-conformance fuzzer-v1 protocol, standard target
entry variables and current GP implementation recorded by the preceding wire,
session, socket and backend contracts. This increment connects them to the actual
application entry point, with explicit host execution policy and Parameters.
Completion checks cover startup refusal, real socket handshake/seed/import/state
queries, consensus refusal followed by a valid import, reconnect reset, local
failure closure and graceful shutdown. These are adapter checks, not a generated
Polkajam conformance campaign.

With JAM_FUZZ defined, startup is isolated before normal option/service selection:

```
ragnarok serve-fuzz CURRENT_POLICY PARAMETERS_JSON MAX_WRITES MAX_WRITE_BYTES
```

CURRENT_POLICY is the existing complete current-download policy format; only its
candidate execution policy is used, without opening download peers. PARAMETERS_JSON
contains the existing protocol_parameters field. Neither a seed nor an incoming
peer can supply or override this trusted configuration. Both file reads are bounded.
The two unsigned write budgets are explicit (at most 1000000 writes and 64 MiB of
write values); zero deliberately disables that resource. Other ignored production
service arguments are refused rather than activating RPC, QUIC, UI or persistent state.
A container entry point may supply these four fixed host configuration arguments.

Standard required variables are JAM_FUZZ, JAM_FUZZ_SPEC (tiny/full),
JAM_FUZZ_DATA_PATH and JAM_FUZZ_SOCK_PATH. JAM_FUZZ_LOG_LEVEL accepts the documented
optional values. Configuration checks exact core/epoch/header-population domains:
tiny uses 2/12/6; full uses 341/600/1023 decoder ceilings. All other Parameters
remain explicit operator configuration; these domain checks do not certify that an
arbitrary supplied tuple equals the engine's complete selected preset. The caller
must supply the same complete profile as the campaign.

Data and socket parent directories must already exist, be private and owned by
the effective user. The data directory is reserved for future optional caching;
this implementation holds all seed/chain state in memory and writes no chain
files. Each frame has a 16 MiB payload cap; complete maps retain the existing
4 MiB/16384-entry local policy. A 30-second absolute request/response deadline
bounds idle, assembling, executing and blocked-output sessions. Explicit limits
are local resource policy, never protocol-invalid block judgments.

The target advertises protocol1, GP0.8.0 and feature mask2: depth-one sibling
execution without initial ancestry. A negotiated fork bit enables eight retained
sibling maps; otherwise the backend remains linear. Every connection gets a fresh backend.
The seed and rolling retained history support exact-header-hash whole-map queries.
Header/map clock incompatibility and missing/evicted lookup context still cause
local closure at actual import; seed acceptance and queries remain exact.

Recognized typed admission, disputes, ticket, marker, seal, assurance and report
comparison failures return Error while preserving the session and prior state.
Unclassified execution failures, resource overruns and internal/context faults
close without an Error. The conservative classifier is explicit rather than
interpreting every failed candidate as a consensus rejection. Additional classes
must gain precise attribution and witnesses before being translated.

SIGINT/SIGTERM request shutdown through a scalar lock-free atomic flag on the
supported Clang Linux/macOS targets. Signal context performs no allocation or
ARC cleanup. The main loop completes the current policy-bounded execution turn,
restores original handlers and closes the owned listener before returning.
A forced kill cannot perform normal application cleanup.

The public minifuzz replay tool requires no polkajam-fuzz engine. Its pinned
examples remain GP0.7.0/0.7.2 and its process status does not reliably signal a
comparison failure; historical sessions must not be treated as GP0.8 campaign
passes. Current-profile live generated campaign validation still requires a
compatible engine and matching complete profile. No campaign Fuzz matrix job is
claimed by this interface increment.

Observed local checks passed the maintained native startup/classification suite,
the real-entry registered E2E exchange and the normal-mode peer parser. E2E
compared all three complete state replies with the existing independent signed
trace, verified consensus refusal then valid import in the same connection,
fresh reconnect state and owned socket removal after SIGTERM.
