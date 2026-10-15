# Assurances codec and AI development evidence

Completed locally on 2026-10-15, macOS 27.0.1 arm64 / Apple M1 Max. Linux CI is wired, but has not
been observed for these changes. This is the authorized next M1 gap, with the same contract and
coverage in Nim, Odin and Mojo. No throughput experiment or crypto/backend change is part of it.

Each candidate passes **21,536 identical independent requests**, including hash-pinned official
2-core/6-validator tiny and 341-core/1023-validator full JSON/bin fixtures. Coverage includes every
configured bit position and representative byte-width transitions; empty and maximum counts;
ordering, duplicate/index and padding failures; truncation and malformed/fuzz inputs; failure
atomicity, trailing destination sentinels, input erasure after decode, and raw overlap probes.
Nine intentional compiler probes reject anchor/signature, index/count and configuration swaps.
The fixed-field records own their bytes, with no retained input pointer or release bookkeeping.

| Metric, this increment | Nim | Odin | Mojo |
| --- | ---: | ---: | ---: |
| Compiler repair iterations | 1 | 1 | 2 |
| Comparable time to passing tests | N/A | N/A | N/A |
| Confirmed native defects found after compilation | 0 observed | 0 observed | 0 observed |
| New production implementation LOC | 125 | 152 | 145 |
| Additional human interventions after registration | 0 | 0 | 0 |
| Confirmed regressions / baseline checks retested | 0 / 1 | 0 / 1 | 0 / 1 |

[The frozen plan](assurances/plan.json), [machine-readable metrics](assurances/ergonomics.json),
[Nim journal](assurances/nim.json), [Odin journal](assurances/odin.json) and
[Mojo journal](assurances/mojo.json) retain actual attempts, source fingerprints, compiler versions,
configuration and UTC timestamps. [Command logs](assurances/logs.tar.gz) have an independent
[hash index](assurances/log-index.json); archived member names match journal log basenames.
Task LOC manifests/snapshots are `assurances/loc-scope-{language}.json` and
`assurances/loc-{language}.json`. They exclude tests, drivers, shared infrastructure and reused
code; Mojo's 12 added Failure-table lines are included. Fewer physical lines are not a quality score.

Nim's one repair parenthesized a raw-byte openArray expression before the prefix sequence-copy
operator in the trusted overlap driver (`assurances-nim-0002.log`). This was syntax/precedence
friction, caught before behavioral testing. Odin's one repair used an unsigned shift amount and
an exhaustive framing-error enum mapping (`assurances-odin-0002.log`). Its exhaustive switch
check prevents an omitted error alternative from silently proceeding; it did not reveal an
observed malformed-input bug. Mojo's two repairs concerned its explicit String byte-length API
(`assurances-mojo-0002.log`) and explicit Failure transfers / homogeneous numeric comparisons
(`assurances-mojo-0003.log`). These are library/language diagnostics; no compiler crash occurred.

Mojo also had one unchanged build retry after shared setup omitted the output directory. The
compiler had accepted source but could not write its target (`assurances-mojo-0004.log`). This is
recorded as infrastructure and contributes no source repair. Deliberate wrong-type probes are
recorded as diagnostics and excluded from repair counts in every language. All direct new-target
builds were wrapped; baseline commands perform existing builds internally and are recorded as
baseline checks, not individual new-target compiler attempts.

Candidate order was **Mojo, Nim, Odin**, counterbalancing the previous **Odin, Mojo, Nim** round.
One agent could inspect earlier implementations. Exact serving-model/reasoning settings are N/A;
GPT-6 family is known. Shared contract/oracle preparation preceded the native edits, while reused
source inspection also preceded some handoffs. Raw final-source acceptance intervals were Nim
**160.38 s**, Odin **191.16 s**, Mojo **244.48 s**. These are real operational wall intervals,
including instrumentation and tests, but insufficiently controlled for a comparative development
speed claim. They are retained as raw measurements; comparable time remains N/A.

The one registered baseline check per language is the existing complete-report suite, built
fresh before and after implementation: **18,198 requests and 42 independent composition checks**.
The one-check denominator is that complete suite, not its assertion count. A separate final
[three-language codec run](assurances/codec-regression.log) passed all **185,373 requests per
implementation**, native tests and existing negative compilation checks. Five new oracle-integrity
examples, thirteen existing report/evidence tests, twelve measurement-tool tests, all nine new
type probes and official formatting checks (159 native source files) passed locally.

A shared review finding corrected the earlier report documentation's tiny profile label: the
pinned vector README says **2 cores, 6 validators**. Native report range validation is already
parameterized and unchanged. The official standalone tiny report codec fixture uses core 3, so
it remains a structural fixture tested with a permissive bound; a new separate two-core rejection
request covers actual tiny eligibility. Historical results are preserved. This is a shared
specification/test-label defect, not three native decoder defects or three regressions.
[Setup notes](assurances/setup-notes.md) retain that distinction.

Across the two new matched implementation tasks, repair observations are Nim **[0, 1]**, Odin
**[5, 1]**, Mojo **[4, 2]**. Cumulative measured totals at the end of that round were **Nim 1, Odin 6, Mojo 6**;
earlier untracked work remains N/A. The [running comparison](ai-ergonomics.md#subsequent-matched-implementation-evidence)
keeps both per-round counts and cumulative totals. This strengthens the limited observation that Nim has needed less
compiler repair in this workflow. The present task gives no defect-rate winner: all three passed
the same checks without a confirmed post-compilation native defect. Nim's architectural ownership
advantage from earlier retained-owner work remains relevant, but these fixed records require no
manual lifetime management in any candidate. Two tasks, shared agent context and unequal ordering
are too little evidence for a general language reliability ranking.

The [API guide](../docs/assurances.md) and [specification](../spec/assurances.md) explain behavior
and limits. This is a structural codec: block-parent equality, validator assignment/state checks
and signature verification are outside it. The existing Ed25519 acceptance-policy gate remains
open. No new networking claims follow from this round.

Reproduce from the pinned toolchains/submodules:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_assurances_harness.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_assurances.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_assurances_types.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_work_report.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_codec.py --mojo
PYTHONDONTWRITEBYTECODE=1 python3 tools/format.py --check
```

The report baseline additionally requires the already pinned native crypto build. Assurances
itself links no crypto, foreign codec or Python runtime. Nim uses 2.2.12 ARC, Clang O3/LTO with all
assertion/bounds/range/field/overflow checks on; Odin uses dev-2026-10:84bc3fc21 `-o:speed -vet
-strict-style`; Mojo uses 1.1.0 (8189361e) `-O3` and its public native SDK. Tool outputs and exact
commands are retained in the journals and snapshots. No toolchain or dependency revision advanced.
