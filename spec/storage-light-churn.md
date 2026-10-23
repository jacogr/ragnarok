# Light-file evidence churn baseline

This maintained benchmark measures the cost of repeatedly changing retained knowledge at one
independently trusted complete root. It introduces no production persistence or protocol change.
Application/startup and consensus selection remain gated; M1 framing completion remains distinct
from full state serialization or JAM client completion.

Run:

```sh
make setup
python3 tools/storage_light_churn_benchmark.py --output build/light-churn-run --samples 5
```

The output directory must be new and under `build/`.
The runner uses the verified pinned compiler, checked ARC/Clang ThinLTO, the maintained crypto
and IO observers, and the existing native publication workload. Generated reports retain binary,
source, compiler, provider and observer identities, raw commands/logs and child receipts.

Two separate native producers create independently rooted 4,096-entry fixtures with 64/1,024-byte
values and canonical 17-node paths. Producers run outside measured child processes. Five fresh
consumers per fixture run serially in alternating fixture order. Each loads its source, initializes
an exclusive destination, executes eight one-key forget/admit pairs, closes, strictly reopens,
checks all values and canonical output, and retires every native/image/proof/lookup owner.
The native phase clock brackets only the 16 updates or only strict reopen; peak child RSS includes
the complete consumer lifecycle. The parent hashes final selected bytes after child retirement.

Every update returns confirmed file/directory synchronization. Exact full-image extents plus one
successful write per operation establish completed application write bytes; these are not device
traffic or SSD wear measurements. Counters require 16 writes, 32 syncs, 16 renames, 160 update hashes
and 73,729 strict-reopen hashes. Unknown evidence during forgetting is checked explicitly and
never becomes authenticated absence. Retained old readers preserve their original values.
ARC retirement must equal the pre-owner baseline. Failed children, mismatched selected files,
changed counters, missing/duplicate samples and derived rows differing from raw output refuse
summary publication. Six grouped Python tests cover adversarial evidence admission.

## Local baseline

The October23 macOS arm64 run used Nimony `4724f66c2e01b17810c844f26575b2317995fda2`.
Five fresh children per fixture passed with identical deterministic work and complete ARC retirement.

| Value bytes | Image bytes | Completed write bytes /16 updates | Update ms median (min–max) | Reopen ms median | Peak child RSS MiB median |
| ---: | ---: | ---: | ---: | ---: | ---: |
|64|4,886,656|78,176,952|168.189 (164.381–169.898)|19.890|17.609|
|1024|8,818,816|141,083,832|287.097 (284.011–322.494)|31.327|36.641|

These are repeated local baseline observations, not an optimization comparison. The timing range,
whole-child RSS scope and warm/local filesystem prevent cold-cache, Linux memory-pressure or
physical power-loss claims. No production compiler/provider/allocator changes were made.

## Next bounded implementation

The measured write volume makes bounded incremental light-proof persistence worth implementing.
Keep the V1 image as the canonical checkpoint/export, introduce an explicitly separate bounded
journal format, preserve independent chain/root expectations, and verify every incoming proof
before append. Strict replay, uncertain-IO poisoning, partial-tail authority, atomic compaction and
real process-crash checks must accompany that backend. No network format or startup integration
is implied. First qualify the existing full-image publication crash boundaries with the maintained
exact-child stop/kill observer, then use this same churn workload for a matched comparison.
