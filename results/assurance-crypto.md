# Assurance signing-context implementation evidence

Completed locally on 2026-10-15 on macOS 27.0.1 arm64 / Apple M1 Max. The authorized third matched
round adds GP v0.7.1 `assurancesig` message composition and stateless parent/key/signature checks
in all three languages. [Contract](../spec/assurance-crypto.md), [API](../docs/assurance-crypto.md)
and [preregistered plan](assurance-crypto/plan.json) identify exact scope and exclusions.
Linux CI includes the new checks but has not yet been observed for this change.

Each candidate passes **2,082 identical independent cases**: exact message bytes across aligned
and partial core widths, every bit of representative profiles, native storage/padding failures,
ordinary independently signed tiny/full batches including maximum counts, key-table/index/order
checks, parent binding, wrong domain/framing/hash-parameterization, corrupted signature bytes,
input immutability and complete structural preflight before signature work. Public-key lookup is
by validator index, including full validator 1022. Maximum batches deliberately reuse three
ordinary test keys across an explicit 1023-entry table; they are not claimed as real chain state.

The oracle uses Python hashlib for Blake2b-256 and OpenSSL for Ed25519. Before generating fixtures,
it reproduces a hash-pinned RFC8032 known answer. Local provider output was OpenSSL 4.0.3; Linux
may have a different independently installed version and must reproduce the same deterministic
request/expected hashes. [Frozen fixture receipt](assurance-crypto/setup.json) and
[per-language checks/metrics](assurance-crypto/ergonomics.json) retain that evidence.

| Metric, this round | Nim | Odin | Mojo |
| --- | ---: | ---: | ---: |
| Compiler repair iterations | 0 | 0 | 1 |
| Measured handoff → first passing final-source tests, seconds | 134.66 | 146.14 | 194.29 |
| Confirmed implementation defects found after compilation | 0 observed | 0 observed | 0 observed |
| New production implementation LOC | 89 | 83 | 95 |
| Additional human interventions after registration | 0 | 0 | 0 |
| Confirmed regressions / baseline checks retested | 0 / 2 | 0 / 2 | 0 / 2 |

These elapsed values are actual wall intervals, including source inspection, implementation,
baseline runs, diagnostics, tests, pauses and instrumentation. Shared spec/oracle preparation was
finished before handoff, and no new candidate implementation analysis/edits preceded its journal.
They are not active coding time or a controlled causal language-speed comparison: a single agent
retained historical context, later candidates could see earlier implementations, provider and
compiler runtime differ, and this is one small task. Exact serving-model/reasoning metadata is
N/A; the known model family is GPT-6. Historical timing fields from earlier rounds stay N/A.

Order was **Nim → Odin → Mojo**. Across the three rounds, every language has now occupied each
position once (previously Odin/Mojo/Nim, then Mojo/Nim/Odin). This reduces one persistent order bias
but does not remove sequential learning or establish independent samples of language reliability.

| Cumulative measured contribution | Nim | Odin | Mojo |
| --- | ---: | ---: | ---: |
| Compiler repairs before this round | 1 | 6 | 6 |
| Compiler repairs, this round | 0 | 0 | 1 |
| **Compiler repairs, total** | **1** | **6** | **7** |
| New-task implementation LOC before this round | 463 | 632 | 658 |
| New-task implementation LOC, this round | 89 | 83 | 95 |
| **New-task implementation LOC, total** | **552** | **715** | **753** |

The [running comparison](ai-ergonomics.md#subsequent-matched-implementation-evidence) and
[hash-linked totals ledger](ergonomics/increment-totals.json) retain every round's contribution.
Cumulative new-task LOC covers only these prospectively tracked increments, not the whole client
or older POC. Tests, drivers, shared infrastructure, dependencies and reused implementation are
excluded. No reused file is counted wholesale again. Mojo's 95 lines comprise 83 in the new
module plus 12 added noncomment Failure-table lines; Odin and Mojo's new modules are each 83.
Physical layout, imports and type/result boilerplate affect LOC; fewer lines are not a quality score.

Nim and Odin both passed their first direct build. Mojo's single repair changed the fixed ASCII
array initialization from an unsupported variadic constructor to the SDK's list-literal syntax.
The actual failure is `assurance-crypto-mojo-0003.log`; `0004.log` is its linked successful repair.
This is library/API friction, not a protocol defect, compiler crash or FFI mismatch. There were no
new infrastructure retries. Six intentional probes reject parent/anchor and message/signature
substitution; all produced the intended wrong-type diagnostics and are excluded from repair counts.
Those are concrete compiler safeguards, not mistakes made during implementation.

No confirmed native defect escaped compilation in the observed corpus or review. That remains a
limited zero-observed count, not proof of absence or a defect-rate winner. The architectural owner
advantages previously discussed for Nim are not exercised heavily here: every candidate uses fixed
owned fields and synchronous borrowed inputs without new release obligations. This task supports
the narrower observation that Nim and Odin were both straightforward for this M2 composition,
while Mojo needed one API repair. Nim still has fewer cumulative repairs; Odin was shorter in this
round. Three small related tasks cannot establish a universal reliability ranking.

Each candidate's two registered baselines were built fresh before and after its edits:
**21,536 assurances requests**, and **18,198 report requests plus 42 independent composition checks**.
A denominator of two means two registered suites, not their assertion count. A separate final
[broader codec run](assurance-crypto/codec-regression.log) passed all **185,373 requests per
implementation**, native tests and existing type guards. Four new oracle checks, five prior
assurances-oracle checks, thirteen report/evidence checks and twelve measurement-integrity tests
passed. Six new nominal probes passed; official formatting passed for **171 native source files**.

The [Nim](assurance-crypto/nim.json), [Odin](assurance-crypto/odin.json) and
[Mojo](assurance-crypto/mojo.json) journals preserve actual compiler commands, source snapshots,
tool outputs, UTC boundaries, raw metrics and deliberate diagnostics. Final checked builds use
Nim 2.2.12 ARC/Clang O3 **LTO only**, with assertions/bounds/range/field/overflow checks ON;
Odin dev-2026-10:84bc3fc21 `-o:speed -vet -strict-style` with runtime checks;
Mojo 1.1.0 (8189361e) `-O3` using the public native SDK. New production protocol storage is fixed,
allocation-free and independent of test fixture utilities. Primitive providers remain unchanged:
Nim/Mojo use the maintained BoringSSL ABI, while Odin uses core crypto.

[Archived command logs](assurance-crypto/logs.tar.gz) are matched by basename to journal paths and
verified against the [SHA256 index](assurance-crypto/log-index.json). Reviewed task-only LOC scopes
and snapshots are `assurance-crypto/loc-scope-{language}.json` and
`assurance-crypto/loc-{language}.json`. Shared receipt/source hashes are in the machine-readable
summary. All final accepted sources match the archived journals; no post-acceptance native edits
were made. CI wiring, documentation and separate shared integrity tests followed candidate closure.

This check does not implement pending-report eligibility, availability supermajorities, state
transition or active-set selection. The caller must supply the correct active keys and expected
parent. The existing exceptional-point Ed25519 provider acceptance discrepancy remains unresolved;
ordinary-key fixtures and preserved backend verdicts do not close that gate.

Reproduce after the existing pinned native crypto build:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_assurance_crypto_harness.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_assurance_crypto.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_assurance_crypto_types.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_assurances.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_work_report.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_codec.py --mojo
PYTHONDONTWRITEBYTECODE=1 python3 tools/format.py --check
```
