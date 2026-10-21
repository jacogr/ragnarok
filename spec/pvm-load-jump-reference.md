# Load-and-jump mutation and alias cross-check

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary:
[load_imm_jump](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L445-L452)
and [load_imm_jump_ind](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L620-L628).
The right-hand input registers precede the specified destination write, which
survives panic or halt.

The independent control corpus appends120 static and1296 dynamic load/jump cases.
Static cases vary six destination nibbles, four sign-bearing immediates and five
valid/invalid targets. Dynamic cases vary six destination/base nibbles each,
six original base values, three signed offsets and two loaded values. Saturated
nibbles15 map to r12; aliases use the original base, including upper64-bit address
patterns. Dynamic addresses cover zero, odd, table entry0, out-of-table and halt
sentinel behavior. A successful prefix and full-register patterns expose lost or
reordered writes.

All384 original conditional records remain byte-identical after the count header;
a provenance test reconstructs their original91884-byte corpus and hash. The new
1800-row corpus hash is
`877eef02d3e691abb7357c5167aa6ade65091055470f84261218bfc1cb8fdf6e`.
Both native replay and the public pinned PolkaVM interpreter check every final
register/exit. Native step traces also compare the causing PC. For opcode0 the
paper's default single-step PC advances, whereas PolkaVM's API reports the causing
instruction; the replay explicitly checks both conventions and GP recursive PC0.
This is API-stage normalization, not an adjusted guest-effect expectation.

All1800 native/public rows and three Python provenance/boundary checks pass.
Corrupting the final appended record fails at row1799/register12. Existing bounded
four-step native and Sync/Full/L2Hit reference execution prevent accidental loops.
No production semantic, source-pin or dependency change. Reproduction uses the
[conditional-control contract](pvm-conditional-control-reference.md). Evidence is
local checked-release macOS/ARC/Clang LTO and pinned Rust, not Linux CI or full
upstream fuzz-suite coverage.
