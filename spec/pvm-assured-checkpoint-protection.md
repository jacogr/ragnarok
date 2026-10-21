# Protected-memory panic retains checkpoint deletion

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/pvm.tex` unconditional protection below2^16 and `text/pvm_invocations.tex`
checkpoint/exceptional selection; vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: ReadCheckpointProtection uses the actual one/two input count branch from
the deletion/read/restoration guest. Count1 halts and creates eleven bytes.
Count2 loads one byte from address0, causing an unconditional protection panic
which selects checkpoint absence. The initial parent and later regular context
both retain a value, so final MissingKey proves exceptional checkpoint selection.
Original authoring precedes refinement/root/signing; no completed data is patched.

The new shared checkpoint witness preserves every assertion from the trap and
guard-fault suites while avoiding three copies of their publication/limit logic.
Each suite still owns its mode, expected output and isolated ARC report. Existing
mode program bytes, policies, production code, pins and parameters stay unchanged.

Completion: all three terminal variants run their exact28/27 steps, copy11/10,
calls3/4, zero final-value-byte/key/provenance limits, metadata/code/gas/parameters,
full state composition/publication/history/activity/finality and alias assertions.
Each executes1000 full successor ARC cycles. Check affected computed-storage and
assured-outcome consumers, inventory, harness tests and pinned formatting.

Wrapping successors now follow [the approved PolkaVM memory ordering](pvm-polkavm-memory-order.md)
through real checkpointed assured execution. M1 framing complete; full state
serialization, whole-block parity and full chainspec equivalence remain open.

Observed: the protection suite and both extracted predecessor suites pass1000
full successor cycles, each retaining753888/753888 bytes. All57 prior assertion
expressions survive the extraction; the shared witness adds one eligibility
constraint. The protected load yields normalized Panic/Exceptional and selects
MissingKey. Exact execution/copy/host/proof ceilings and full canonical publication
assertions pass. Inventory and37 native-harness tests pass. Local checked-release
macOS/ARC/Clang LTO evidence; remote Linux CI remains separate.
