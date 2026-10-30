<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Experimental PVM evidence machinery — preservation only

This tooling-only draft preserves seven previously ignored author helpers **byte for byte**.
`manifest.json` binds each copy to its original path, SHA256, frozen source, run and retained
evidence. No experiment, runtime change, default, CI dispatch or adoption is introduced.
No binaries, generated sources, credentials, raw artifacts or caches are committed.

## Already committed machinery (do not duplicate)

| Frozen experimental branch | Exact head | Reusable entry points |
|---|---|---|
| `codex/pvm-region-coverage-diagnostic` | `8bdaac76535552fad6c308374ba72d9cbb2604a2` | `tools/pvm_region_diagnostic.py`, its parser tests and literal observer controls |
| `codex/pvm-doom-e2e-audit-copy-1` | `fdd863842221f43497e21345d021d846d14042a5` | `tools/pvm_doom_e2e.py`, `tools/pvm_doom_timing.py`, Nim/Rust matched-caller adapters |
| PR1855 source via `refs/pull/1855/head` | `5dd1de0ef162c1d90f134e7771f1178856d3c228` | ARM refusal fixture/gates; failing reproducer `dcbd1ce59ff3c48ef874101bd7e6c870237844fb` |

These branches preserve experiment provenance, **not accepted production**. The new preservation
branch contains no experimental runtime delta. The observer/runtime-containing branch stays
separate and frozen. PR1855's narrow fix alone merged as `ef5b4a3514b5bcbf8fc488366140a8c634c1f5bd`.

## Restore historical paths before use

The archived scripts are cohort-specific recipes, not a relocatable Python package. **Do not
import or execute them at their archive paths.** Some derive the repo root from their original
`build/` path; others contain the original absolute checkout path. Preserve those assumptions
for exact replay, or separately review future path adaptation. Several execute at import time.

Future authorized replay, in the original checkout with the retained artifact directories already
present, can restore a helper from this draft's immutable commit. Use a fresh target path; stop
instead of overwriting an existing different helper. For the regional audit, for example:

```sh
archive_commit=$(git rev-parse origin/codex/experimental-pvm-jit1-evidence-tooling)
git fetch origin codex/pvm-region-coverage-diagnostic
git switch --detach 8bdaac76535552fad6c308374ba72d9cbb2604a2
mkdir -p build/arm-region-refusal-work
test ! -e build/arm-region-refusal-work/audit-region-diagnostic.py &&
  git show "$archive_commit:tools/experimental/pvm_evidence/region_audit.py" > build/arm-region-refusal-work/audit-region-diagnostic.py
python3 build/arm-region-refusal-work/audit-region-diagnostic.py
```

Match the restored bytes to the manifest before running. If the target already exists, compare
its hash rather than overwriting it. The examples are future replay instructions, not a request
to run a new campaign. All auditors are inert with respect to project native images; never
execute a downloaded binary. They do read data, invoke Git/host decompression, and write ignored
audit receipts. Download helpers use authenticated `gh`, never extracted credentials.

| Archive helper | Original entry point after restoration | Scope |
|---|---|---|
| `region_audit.py` | `python3 build/arm-region-refusal-work/audit-region-diagnostic.py` | Run41059179556, checkout8bdaac, existing original ZIP/API/extracted evidence |
| `arm_audit_baseline.py` | `python3 build/arm-region-refusal-work/audit-baseline.py` | Run41051261233, intended historical native failure, not a passing comparison |
| `arm_download.py` | `python3 build/arm-region-refusal-work/download-evidence.py 41051261233 dcbd1ce59ff3c48ef874101bd7e6c870237844fb` | Fetch original ARM artifact only; network/data writes, no new CI |
| `arm_gas_oracle.py` | `python3 build/arm-region-refusal-work/gas-oracle.py` | Pinned GP oracle;50 small cross-checks before the literal long fixture, no production oracle change |
| `doom_audit.py` | `python3 build/doom-e2e-work/audit-copy-fix-full.py build/pvm-doom-e2e-evidence/41031037331` | Checkoutfdd86384; requires retained build-only41028220399 images and pinned golden input too |
| `doom_download.py` | `python3 build/doom-e2e-work/download-evidence.py 41031037331 fdd863842221f43497e21345d021d846d14042a5` | Fetch the two original sealed artifacts, never rerun their cohort |
| `doom_copy_loop.py` | `python3 build/doom-e2e-work/inspect-copy-fix-asm.py` | Exact eight retained41028220399 listings/symbol offsets, not a generic compiler proof |

The DOOM scripts require the fdd86384 checkout and original absolute workspace. The gas helper
requires the unchanged test oracle and GP1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d sources.
No copied script is newly functionally qualified by this preservation commit: copies receive
only byte-identity/syntax inspection, reusing their recorded historical evidence.

## Preserved outcomes and unfinished limits

- Regional run41059179556: final independent **REGROUP**. No extra-slot/residency trial follows.
  History is not cleared across native regional returns; no reachable bad count was reproduced.
  Exclude closed-cycle attribution; direct counters/selfloops are separate. Capped scans and
  incomplete boundaries forbid a global no-optimization conclusion. ARM explicitly reserves
  its1024th slot; x86 shares1024 between ordinary/regional publications. The frozen diagnostic
  spec's blanket1023 wording is imprecise; quota code was unchanged. Observer remains unadopted.
- DOOM41031037331: qualified only the fixed matched immutable-caller scopes. It is not general
  VM/JAM gas, uninterrupted-gameplay, arbitrary-exit or eager-runtime adoption evidence.
  Unequal-scope41004352868 and timed-out41017859851 remain rejected/incomplete, not rerun or erased.
- `audit-fixed.py` is excluded: its mixed native-row schema caused a KeyError. Transient
  dispatch/publish scripts, superseded audits and other chats' tooling are not promoted.
- Original data stays under ignored `build/` paths in the manifest. Git does not back it up;
  Actions artifacts expire. Missing originals cannot be replaced with reconstructed PASS claims.
  Independent receipts and complete manifests remain adjacent to each retained cohort.
