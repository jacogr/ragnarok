# Checked register runs

## Scope and authority

This bounded interpreter experiment starts from master `4a29188758026f062e2b970b96df2665d8764d4e`.
The pinned Gray Paper 0.8.0, PolkaVM revision, Nimony toolchain, program format, gas rules and
public execution API are unchanged. The existing source-owned `FlatFact` operands and register
equations remain authoritative. No native opcode, memory path or host callback is changed.

Explicit `interpreted` plans may replace the first ordinary handler of four or more consecutive
register-only instructions with one checked run worker. Each later source operation retains its
original stream node, so an interior entry and a partial source-attempt barrier still select the
same byte PC. The run uses operands and opcodes sealed from source facts and private frame registers.
It stops before a control, host, memory or folded-noop boundary. Gas remains a whole-block charge
at the original header; the run makes no pricing decision. Default `jit` plans retain their
original handler identities and native scanner behavior.

The first run node stores its bounded operation count and opcode in the register operand record's
otherwise unused secondary word. Later run nodes store their opcode there too. The existing node, source-index and operand arrays remain the complete
execution representation. No new frame, plan, stream or native ABI fields are introduced.

## Qualification

The `pvm_checked_register_runs` native suite uses a literal six-operation mixed arithmetic run
with aliased registers and a trap. It compares the explicit interpreted plan with the default policy at
every source-attempt budget, with paid and unpaid gas, zero and sufficient gas, reordered interior
entries and repeated calls after temporary barriers. It also requires the literal final register
value and retained original source. Existing all-opcode, prepared, host, fault and backend-policy
suites cover the unchanged fallback and public boundaries.

Local verification is limited to pinned semantic checks, formatting and inventory. Native
compilation, execution and timing belong to CI for this performance increment. A retained change
requires same-run baseline/candidate interpreted measurements using identical inputs and checked
build profiles, both process orders and complete state/output controls. Source-level success alone
does not establish a speedup. Record any rejected timing hypothesis here and remove its runtime
change if the measured benefit does not justify the extra dispatch path.

The existing application cohort compares current interpreted policy with a previous JIT policy,
which cannot attribute this interpreter-only change. Manual `jit-arm-profile` or `jit-x86`
dispatches therefore opt into `pvm_interpreter_pair` with a full `pvm_prepared_baseline` commit SHA.
That mode builds the baseline source twice under the same native flags and requires equal images
for baseline `jit` and baseline explicit `interpreted` policies. It then checks both interpreted
roles against the same fixtures, refusal controls and 13-call process samples in both orders.
Ordinary runs retain their existing five-role cohort and JIT comparison.
