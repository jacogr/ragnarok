# Executable authenticated node

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` and Gray Paper
`3861aed15d7d016a3a416e14e61fc67dddf6daec`, Overview Common Era and timeslots.
No dependency, specification or toolchain pin changes.

The ordinary `node` command activates the existing managed application actor and Services:

```sh
ragnarok node --with-state --chain chain.json --node-finalized HASH
```

`HASH` must be exactly 64 lowercase hexadecimal digits identifying an operator-trusted finalized
block already present in the selected canonical view. Full-state startup is required; neither best,
recovery metadata nor peer claims implicitly establish finality. An unavailable selected hash fails
before the node UDP actor starts. Explicit finality is an operator assertion, not a network consensus
certificate. Memory and supported full-state disk/recovery selections keep their existing Services
startup contracts. Partial/light mode is refused at the command boundary.

Named network port/bind/certificate/key controls apply. The port defaults to 34100; omitted
credentials are generated once through the existing private persistent identity path and reused.
Local bind selection keeps the existing transport default when omitted. Workload/dialer-only controls
are refused. The original configured genesis supplies base ALPN, including after restored progress;
a conflicting explicit ALPN fails. Selected canonical parameters bound topology: cores 2..341,
epoch slots 1..4096, roster policy up to three times the core count, accumulator 4096 and chapter
bytes 1 MiB. The actual current roster can be smaller than that policy maximum. Fixed 16384 raw
routes accommodate the largest supported authenticated topology; existing per-peer/global read
and byte limits still apply. No wire callback retains or accesses the canonical map.

The clock uses the pinned GP Common Era, noon UTC on 1 January 2025, Unix 1735732800 seconds.
The selected profile supplies its nonzero slot period. Conversion checks the lower time bound and
32-bit slot ceiling before narrowing. Clock failure or backwards local slot movement stops through
normal cleanup; peer slots and announcements cannot supply time. Monotonic time drives native
polling and optional finite deadlines independently of wall time.

`--net-timeout-ms` defaults to 0, an interrupted foreground lifetime. Positive bounds up to 120000
use monotonic elapsed time. SIGINT/SIGTERM handlers are installed before Services setup and stay
installed through native retirement and joined worker cleanup. One stable `ApplicationNode`
borrows one stable Services address; all returns retire the actor before Services and restore prior
signal handlers last. Managed inbound canonical read workers retain their exact graph/RPC leases.
Optional RPC, UI, MCP, management and telemetry retain their existing explicit activation controls
and tick through the shared Services loop. The entry point reports `NODE_STOPPED` only after owned
cleanup returns; setup/runtime refusals return a typed `NODE_FAILED` cause and unsuccessful exit.

Verification:

- `jamnp_node_command`: clock era/rounding/zero-period/32-bit overflow boundaries; named
  CLI/default/help and invalid/full-mode/hash checks; unknown local finality and conflicting ALPN;
  actual foreground loop on its own thread, authenticated TLS UP0 and CE129 state serving,
  independent trusted-root reply verification, finite deadline and real process SIGTERM shutdown.
  Fresh canonical input is loaded from a file; the test's independent main-thread trust owner is
  never shared with the command's worker graph. Scalar atomic completion follows owned cleanup.
- `startup_identity`: ordinary node default identity provisioning/reuse plus existing private-key
  permissions, incomplete bundle and symlink refusal controls.
- `app_cli`, `app_options`: foreground help/default agreement, refusal of ignored remote-address
  controls and existing CLI/options/ARC consumer regressions.
- Formatter checks, application build and actual built entry-point deadline/SIGTERM smoke runs
  cover CLI dispatch, logger startup/draining and complete foreground teardown.

This command activates authenticated topology, UP0 and managed CE128/129/143 responders.
Autonomous synchronization/GP execution/adoption and the remaining runtime protocol families
remain open; active transport and query service do not imply a complete validating node.
