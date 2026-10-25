# Offline published trace checking

The production application now accepts:

    build/ragnarok check-traces CURRENT_POLICY GENESIS TRACE [TRACE ...] \
      --with-state --chain CONFIGURED_CHAIN \
      --state-writes 1000 --state-write-bytes 1000000

CONFIGURED_CHAIN is the existing strict JSON representation containing the full
protocol_parameters tuple, genesis_header and genesis_state mapping. It independently
supplies trusted header/state identity and the complete chain profile. GENESIS uses
the pinned vectors' published Header + RawState binary representation; every TRACE
is one exact published pre-state + block + post-state file.

CURRENT_POLICY uses the existing ragnarok-current-download-policy-v1 format.
The checker consumes its current-candidate limits. File processing uses bounded
regular-file EOF for the policy, configured chain, Genesis and each trace.
The configuration cap is8MiB, each binary file cap16MiB, and one invocation accepts
1..256 consecutive steps. Existing state mutation defaults and explicit zero
overrides remain in force. Exact retained ancestor count/bytes are checked against
the supplied candidate policy before further private execution.

The command permits only explicit state activation, configured-chain path and
state mutation budgets. Listener, disk, recovery and download controls are refused
during atomic option parsing. The command performs independent Genesis trust/profile
binding, authenticated STF preparation, complete pre/post map comparison and normal
guarded continuation on a private ephemeral chain. Every descriptor/owner retires
before return. Configured files remain read-only; execution creates no Services,
listeners, transport callbacks or persistent state database.

Success prints TRACE_CHECK_OK with checked count and the actual verified final root.
Failure prints TRACE_CHECK_FAILED with the typed command stage, checked-prefix count
and a bounded nested-stage diagnostic. A failed command exposes no successful final
root, prepared update or external chain owner. Checked-prefix counts describe only
the private offline invocation.

The independent corpus materializes40 full-profile configured-chain/Genesis/trace
bundles containing255 signed transitions. Full122-byte parameter tuples are authored
from explicit widths and values, never inferred from roots or encoded by the native
checker. These are deliberately configured test profiles, including zero deposits
and7/1/100 deposit schedules; they are not implicitly the standard Tiny profile.
Existing independently calculated complete maps and signatures are unchanged.
The maintained native helper supplies resource-policy input only, through the
already supported policy encoder.

Six separate refused invocations cover wrong independently anchored Genesis state,
trailing Genesis bytes, recommitted wrong post-state, trailing trace bytes, wrong
pre-state and a later altered seal. The last case confirms a one-block checked prefix
without an external mutation. Every configured expected input and output hash is
frozen before execution.

Native options/command tests cover absent activation, default/failed owners, missing
policy, finite cardinality, preserved zero budgets and refusal of unrelated controls.
The common unchanged guest policy moves into a shared test helper; Genesis/gas-exit
regressions preserve its existing behavior. Public driver checks, the actual
production binary, privacy guards, semantic checks, independent configuration/
framing invariants, pinned formatter idempotence and inventory cover completion.
Local ARC/Clang evidence remains separate from exact-head Linux CI. Pins, historical
fixtures, STF algorithms and AmbiguousPrivileges are unchanged. A matching independent
external engine/profile is required for external-client differential conformance.
