# Explicit download startup

## Scope and authority

Launch the [bounded dispatcher](application-download-loop.md) from the existing
application entry. Preserve GP 0.8.0, recorded vectors and JAMNP-S
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`. No wire or consensus rule changes.

## Contract and completion tests

The command is `download PORT CERT KEY PEER ALPN TIMEOUT POLICY`, followed by
explicit `--with-state --chain FILE --state-writes N --state-write-bytes N`.
PORT is an existing loopback peer; PEER is exactly 32 public Ed25519 bytes.
TIMEOUT is a positive dispatcher-run duration up to 120000 milliseconds. It is
sampled between bounded turns and cannot preempt synchronous state/PVM work. POLICY
supplies every dispatcher, stage and composition value. No default network
profile, gas configuration or execution budget is inferred. This first command
supports one explicitly pinned peer (local ID 1), no ancestor provisioning, and
one child. RPC/UI may share the canonical Services owner. Telemetry activation
is rejected until concrete outgoing-endpoint lifecycle reporting is integrated.

Policy v1 is a bounded UTF-8-compatible ASCII key/value document beginning with
`ragnarok-download-policy-v1`. Its explicit dotted keys follow DownloadLoopLimits;
all 314 leaves must occur exactly once. The [frozen schema](../src/app/download_policy_fields.nim)
lists their exact names. Each is canonical unsigned decimal,
including explicit zero where a stage permits it. Reject unknown, duplicate,
missing, signed, non-decimal, overflowing and narrow-width values. Blank and
comment lines after the header are allowed; keys/values have no surrounding
whitespace. A final newline is optional. The 64 KiB byte limit applies before
parsing or file allocation beyond limit+1; bounded line/key/value counts constrain
startup work. The schema is explicit source, with no runtime reflection or silent
field fallback. Frozen v1 field names require deliberate version review when
stage APIs change. Stage implementations retain semantic-policy authority.

Parsing returns a private tagged result: defaults/failures never expose a partial
policy. Successful extraction copies plain nominal policy values. Encoding an
explicit caller policy emits every field for configuration tooling, and does not
certify that its stage policies are usable for a selected chain.

Startup validates arguments, bounded files, outer dispatcher policies and raw
application admission before opening outgoing transport. Services may start
explicit RPC/UI listeners only after input preflight. Stable stack owners retire
dispatcher callbacks before Services on every success/failure/timeout path. One
millisecond bounded host pauses avoid spinning between nonblocking dispatcher
ticks. Actual adoption alone reports success; exhaustion, invalid candidates,
identity rejection and command timeout return failure. No response supplies a
serving endpoint or an adoption acknowledgement.

Tests cover complete policies, full uint64 values, every missing field, unknown
and duplicate keys, narrow overflow, truncation, file bounds, atomic/default
results, nominal values, startup gates, actual pinned TLS command execution,
actual entry preflight dispatch, deferred adoption/refusal, bad policy/key/missing FIN,
ARC retirement and strict compiler/runtime guards.

## Verification

Local macOS evidence with pinned Nimony nightly
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, ARC and checked optimized Clang/LTO:

- `make unit SUITE=application_download_startup` passes real command adoption,
  wrong-key rejection, missing FIN, empty exhaustion, genuine guest preparation
  refusal, whole-run timeout, exact identity width and bounded startup files.
  Every one of 314 missing fields is rejected with its exact name; unknown and
  duplicate fields, malformed numbers, full uint64 maximum and page-width
  overflow are covered. Immutable copies cannot mutate retained policies.
- 1,000 complete/failed policy cycles retain exactly 236,704 occupied bytes
  before and after. Two result privacy probes, three exact runtime extraction
  defects and a genuinely successful result control pass.
- `make build` succeeds with the actual application entry and both maintained
  features. Its persistent executable controls pass 41 refusal cases, including
  exact new-command preflight, plus help/version/parser/I/O selftests.
  Actual adoption is exercised through the command API in the native suite;
  this is separate from the executable preflight controls.
- `make unit SUITE=app_options` passes. All 56 native harness, 35 verification
  harness and 11 inventory harness tests pass. Pinned formatting, inventory,
  feature/design links and whitespace checks pass; inventory discovers 232
  suites, 163 failure families and 2,032 declared probes.
- Official native reconciliation onto `3dcaddd0` preserves all eight parent
  patches and this startup patch exactly. Published parent trees match the
  reconciled trees. The shared JSON writer move retains identical bytes;
  startup, production build and executable controls pass again after the move. No toolchain, submodule, dependency or wire change is made. Pinned
  reflection probes were unsuitable; production policy loading uses explicit
  typed schema source instead, with no compiler/plugin workaround.

Evidence remains under `build/download-startup-*` and
`build/tests/native/selected/`. Exact-head Linux/full CI is separate evidence;
opening this PR does not request it.

## Remaining work

Peer lists/discovery, explicit ancestors, outgoing telemetry, serving/fork choice,
bounded execution workers and persistent full/light stores remain open. M1
framing is complete; full state serialization/JAM parity remains open.
