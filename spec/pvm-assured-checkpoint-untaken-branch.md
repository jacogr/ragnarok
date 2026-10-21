# Untaken invalid branch selects checkpoint deletion

## Specification and fixture

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix PVM
conditional-jump definition (`text/pvm.tex` lines254–260), requires both destinations
to be basic-block starts regardless of the condition. Negative-target gas pricing
uses the scoped GP-PVM-003 interpretation in the
[discrepancy register](graypaper-discrepancies.md). Pinned PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`, interpreter `emit_branch`, likewise
selects invalid-branch trap before testing register values. No new discrepancy,
production behavior or source revision is introduced.

The original guest fetches and preserves the actual input count, deletes storage,
checkpoints absence, reads NONE and restores eleven regular bytes. Count1 takes
the genuine regular halt. Count2 reaches `branch_eq_imm r6,1,-32768`: the condition
is false, but destination validity must still panic and choose the saved deletion.
Taking fallthrough would instead reach the regular refinement-return block and
commit the restored value, so canonical MissingKey detects a condition-first bug.

## Completion

Use the complete shared checkpoint witness for exact28/27 steps, copy11/10,
call3/4 refusals, key/provenance/zero-selected-byte limits, original gas and account,
parameters, canonical publication/history/activity/finality and source aliases.
Require1000 full successors with unchanged ARC occupied memory. Run the new suite
and predecessor register-branch consumer, pinned formatting and inventory checks.
M1 framing remains complete; full state serialization, whole-block parity and
full chainspec equivalence remain open.

## Observed verification

The untaken immediate-branch suite and predecessor register-branch suite each pass
1000 full successor publications with753888 occupied bytes before and after.
Every exact resource boundary and canonical/alias assertion remains active.
Inventory passes219 failure families/2562 probes/340 native suites; pinned
formatting passes2584 Nim sources and the Rust crate. Local checked-release
macOS/ARC/Clang LTO evidence; remote Linux CI was not requested.
Logs are retained under `build/pvm-untaken-checkpoint-*`.
