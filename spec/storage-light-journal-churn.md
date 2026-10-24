# Matched full-image and light journal churn

This maintained clean-room comparison measures the standalone light persistence contracts on
identical inputs. It changes no production persistence, trusted root, protocol encoding,
compiler/provider/allocator pin or application integration boundary.

```sh
make setup
python3 tools/storage_light_journal_benchmark.py --output build/light-journal-pair --samples 5
```

Use a new output directory under `build/`. Three, five or ten paired rounds are supported.
Separate native producers construct the same independently rooted 4,096-query fixtures with
17-node inclusion proofs and 64/1,024-byte values used by the
[full-image baseline](storage-light-churn.md). One checked ARC/Clang ThinLTO binary runs both
backends. Every mode/size/round has a fresh process and exclusive namespace; both backend and
value-size orders alternate between rounds. Producers are excluded from consumer resource receipts.

Both backends retain a pre-edit reader, execute eight identical one-key forget/admit pairs,
close, strictly reopen, verify all values and the final exact canonical image, then retire every
owner to its ARC baseline. Timing brackets updates or strict reopen separately; peak RSS covers
the whole consumer lifecycle. Initialization, compaction and cleanup are outside update counters.
The journal remains at checkpoint epoch one with all sixteen authenticated frames. Reopen must
authenticate the checkpoint and every frame; it cannot jump directly to the final image.

Exact expected application bytes are `8*(2*imageBytes-(1129+valueBytes))` for full-image publication
and `8*(500+1088+valueBytes)` for journal append. These are completed application write extents,
not device traffic. Full-image work requires 16 writes, 32 syncs, 16 renames and 160 update hashes;
journal work requires 16 writes, 16 syncs, no renames and 176 update hashes. Reopen requires
73,729 and 73,907 hashes respectively. The extra journal hashes do not describe total CPU work:
each frame also reconstructs and checks a canonical successor image.

The parent binds source/pin, compiler, binary, native-library and fixture identities; observes
fresh-child RSS/fault counters and native exit; verifies unchanged inherited limits; and checks
exact checkpoint bytes and final journal extent. Raw output is re-admitted before summary
publication. Missing/duplicate/reordered samples, weaker counters, altered images, bad namespace
identities, invalid receipts and failed retirement refuse a successful summary. Six grouped
paired-admission tests complement the six existing full-image admission tests.

## Local paired observations

Two final three-round panels passed on October 23, macOS arm64, pinned Nimony
`4724f66c2e01b17810c844f26575b2317995fda2`. Each panel has twelve fresh consumers and two
separate producers. Deterministic work and ARC retirement agree across both panels. The second
panel observed:

| Value bytes | Backend | Completed write bytes | Update ms median (min–max) | Reopen ms median | Peak RSS MiB median |
| ---: | --- | ---: | ---: | ---: | ---: |
| 64 | Full image | 78,176,952 | 160.473 (158.104–160.933) | 19.293 | 17.719 |
| 64 | Journal | 13,216 | 143.184 (134.748–151.051) | 152.536 | 27.062 |
| 1,024 | Full image | 141,083,832 | 277.617 (269.847–278.205) | 30.870 | 36.750 |
| 1,024 | Journal | 20,896 | 238.818 (234.704–239.321) | 267.263 | 53.797 |

The write-volume and barrier reductions are deterministic for this workload. The observed timing
and RSS tradeoff matters: journal reopen reconstructs sixteen successors, and whole-image
successor preparation remains material. This panel establishes no general speedup, cold-cache,
Linux pressure or hardware power-loss claim. Exact-head Linux CI remains separate.

Further work should bound encoded-log buffering separately from image reconstruction and keep
this matched panel to detect changes in both replay and update cost. Streaming a short journal
alone should not be presented as a solution to the larger whole-image transient footprint.
