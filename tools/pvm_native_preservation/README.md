# Native experiment machinery preservation

This is an experimental source archive for future reuse. Publication does not
adopt a runtime candidate or qualify these helpers against current master. The
preservation PR is based on the frozen standalone snapshot, not on master; its
diff contains only this archive, manifest and source-restoration utility.

[manifest.json](manifest.json) records full source SHAs, recovery branches,
historical CI run IDs, retained local evidence paths, recorded result hashes,
toolchain identity and a SHA-256/size for each archived script. Paths in that
manifest are relative to the original checkout unless explicitly absolute.
Raw artifacts, binaries, generated guest code, caches and toolchains are not
included. Recorded result hashes describe the retained historical receipts;
this preservation pass does not rerun their qualification.

## Already committed machinery

The `codex/pvm-native-archive-standalone-54d74418` branch preserves the existing
whole-image compiler/generators, measurement harnesses, controls and experiment
specifications at `54d74418d0f1c71523f7ded9cfa75e34a2e1e976`. These were not
recommitted or cherry-picked into the preservation commit:

- `tools/pvm_whole_{sieve,pinky,memory,width,fault_pc,read_cache}.py`;
  `tools/pvm_whole_{memory,width,fault_pc,read_cache}_projection.py`.
- `tests/performance/pvm_whole_image.{nim,h}`, whole-image drivers/frame,
  `pvm_whole_memory/` fragments, typed width/fault-PC/read-cache controls.
- The corresponding `tests/test_pvm_whole*.py`, Make targets and
  `spec/pvm-whole-*-experiment.md` specifications.

`codex/pvm-native-archive-cohorts-aef172ac` preserves the historical CI
measurement adapters (`tools/pvm_eager_*.py`, native handoff data/diagnostic/
profile helpers and their controls) at
`aef172ac2034d692d5e52c70fff945eeae96e019`. Additional policy, owner and DOOM
qualification snapshot branches retain earlier source identities that are not
ancestors of this cohort branch. All five refs and their full SHAs are in the
manifest. These are frozen recovery refs, with no production adoption implied.
Check out the exact measured source SHA for a particular receipt, rather than
assuming an archive branch tip has the same source identity as every old run.

## Newly preserved scripts

The 31 original Python source files are inert `.py.txt` payloads, copied
byte-for-byte from this checkout's ignored `build/` directories. One identical
read-cache audit alias shares its payload. The groups are:

| Group | Purpose |
| --- | --- |
| `historical-ci-audits` | Source/owner/policy, continuing-cohort, visit, handoff and connected/useful-span audits; summary adapters. |
| `standalone-audits` | Whole-image cohort, correctness/comparison audits and Pinky report rendering. |
| `original-profile` | Original helper-heavy Pinky profile preparation, execution and attribution. |
| `width-profile` | Exact width-specialized profile preparation, execution and attribution. |
| `cache-counter-diagnostic` | Clock-disabled, source-sealed final-cache counter diagnostic. |

Some scripts embed historical run IDs, source pins and absolute paths. They
remain historical adapters and may require explicit adaptation for a new
checkout or cohort. The profile and counter `run.py` scripts execute native
code; they require the original standalone ARM64 gasOFF scope and fresh human
authorization for a new experiment. The DOOM timing audit is an old helper from
before ownership transferred to JIT; it makes no claim about the final/current
DOOM cohort. Standalone whole-image code cannot yet run representative DOOM.

## Restoration and reproduction entrypoints

The stdlib-only utility lists or verifies archived source without importing it:

```sh
python3 tools/pvm_native_preservation/restore.py
python3 tools/pvm_native_preservation/restore.py --action verify
```

For reuse, restore the chosen group into an explicitly selected historical
checkout. Keep the archive available separately when switching source revisions:

```sh
python3 /path/to/archive/tools/pvm_native_preservation/restore.py \
  --action restore --group standalone-audits --root /path/to/historical-checkout
```

The restorer writes only the manifest's `build/**/*.py` targets, checks payload
hashes, skips identical existing scripts and refuses symlinks or differing
existing content. It does not restore artifacts, check out revisions, invoke
Git, compile, execute guests, or run any archived script.

Historical audit entrypoints, with matching source and retained input bundles,
include:

```sh
python3 build/audit-connected.py build/pvm-eager-connected-evidence/40996115535
python3 build/audit-useful-span.py build/pvm-eager-useful-span-evidence/40980700138
python3 build/audit-pvm-handoffs.py build/pvm-handoff-evidence/40969195931/pvm-native-handoffs-arm64-1
```

Audit/report writers can replace derived summaries and later addenda. Use a
working COPY of an evidence bundle; preserve original receipts and outputs.
Profile preparation/execution similarly belongs in a fresh experiment checkout,
never in a retained run folder.

Existing measurement reproduction targets, for a separately authorized new
trial at the appropriate pinned source, are `make check-pvm-whole-sieve`,
`make check-pvm-whole-pinky`, and `make check-pvm-whole-{memory,width,fault-pc,read-cache}`
with their `-compare` variants. The manifest and experiment specifications pin
source, toolchain, inputs and retained oracles. These commands are references;
none was executed during preservation. Historical source/identity guards are
intentional and must not be bypassed to qualify a different experiment.

## Scope and retained outcomes

The source archive separates measurement machinery from the experimental
runtime/compiler implementations already in the frozen base. No production
source, master/defaults, or acceptance policy was changed by preservation.
The original chunk-lease rejection remains rejected. Width specialization was
kept for the standalone experiment. Compact fault-PC retains its original
strict-rule DISCARD and separate later human qualified KEEP for code footprint;
runtime remains tentative. It remains the general standalone baseline.

The read-cache experiment retains its original cross-workload DISCARD and the
later human assessment: **promising CONDITIONAL candidate pending representative
DOOM evidence**. It was not rejected as universally undesirable. No DOOM
extension, fresh measurement, review request, CI dispatch, or production adoption
is part of this archive. Original independent proof files and later assessments
remain at the retained artifact paths, separate from these source payloads.
