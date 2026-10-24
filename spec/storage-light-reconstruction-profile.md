# Light successor reconstruction profiling

## Scope and reproduction

This standalone storage investigation preserves canonical V1 image/frame bytes, independently
supplied chain/root, proof authentication, pinned compiler/provider/allocator and checked ARC
release builds. It does not integrate state, PVM or application storage.

```sh
make setup
python3 tools/storage_light_journal_benchmark.py --output build/reconstruction-baseline --samples 3 --include-batch
python3 tools/storage_light_reconstruction_profile.py --panel build/reconstruction-baseline --output build/reconstruction-profile
```

The sampler requires macOS `/usr/bin/sample`. First it re-admits the panel's raw results and
checks current source, compiler, binary, observer and fixture identities. It then runs six
fresh journal consumers, alternating 64/1,024-byte fixture order over three rounds, and captures
one-millisecond stack samples. Each consumer independently witnesses all sixteen updates,
strict reopen, exact canonical final image, retained reader values, hash/IO counts and final
ARC retirement. Sampling failure, child failure, changed inputs and missing call graphs refuse
completion. Raw logs, sample files and source-bound result records remain under `build/`.

Samples start after process launch; startup and early update work can be missed. Stack counts
are statistical observations, not deterministic instruction counts or additive phase timings.
Instrumented child timings and RSS are not a replacement for the separate matched panel.
Linux profiling and exact-head Linux CI remain separate work.

## Initial evidence, October 24, 2026

The source tree at master `caf6e2e41191da29b2801397e728ac4706b2e9bb`, pinned Nimony
`4724f66c2e01b17810c844f26575b2317995fda2`, macOS arm64 checked ARC/Clang LTO, passed a
three-round full-image/journal/batch panel. Ordinary journal reopen medians were 156.728 and
277.921 ms; peak RSS was 27.094 and 53.828 MiB for 64/1,024-byte values. Journal update
medians were 138.979 and 245.756 ms. These are local warm-process observations.

The three 1,024-byte profiles observed 212/215/221 samples in frame replay. Under the successor
edit, 122/124/125 samples were in Blake2b compression and 84/87/90 were directly in the
image-edit loop. The three 64-byte profiles showed the same concentration: 64/66/78 samples
in successor hashing and 48/53/52 directly in the image-edit loop. Cache update and encoded-log
reading were small in these sampled paths. Raw evidence: `build/storage-db5-baseline/` and
`build/storage-db5-profiles/`; no general timing ratio follows from sampling.

The next bounded hypothesis is to replace per-byte retained-entry copies with bounded bulk
copies between distinct immutable source and newly allocated output images. Keep the exact
preflight, complete successor checksum, proof verification and retained-reader semantics, and
compare fixed-work panels before/after. Hash compression remains necessary for V1's complete
successor-image checksum; changing the format or dropping checks is outside this investigation.

## Bounded retained-entry copies

`light_snapshot.edit` copies each retained canonical entry using `copyMem` after explicit
source/footer and output/footer extent assertions. The source is an immutable held owner; the
output is a distinct freshly allocated byte sequence. There is no overlap, borrowed pointer
escape, checksum omission or change to canonical ordering. Incoming proof encoding and complete
image checksum computation are unchanged. The existing native-size preflight still precedes
allocation and pointer formation.

The update suite additionally removes/re-admits each of 27 keys with 0/1/31/32/63/64/65/255/1,024
byte values. Every omitted image matches independently prepared canonical bytes and strict
restore; old and rebuilt readers retain every fixture value. Existing exact-capacity mixed edits,
provider refusal, immutable transport and 1,000-cycle ARC qualification remain in place.

The first matched three-round candidate panel (`build/storage-db5-span-panel/`) observed:

| Value bytes | Mode | Update ms baseline → candidate | Reopen ms baseline → candidate | Candidate RSS MiB |
| ---: | --- | ---: | ---: | ---: |
| 64 | Full image | 169.099 → 121.572 | 19.976 → 19.812 | 17.734 |
| 64 | Journal | 138.979 → 90.306 | 156.728 → 108.271 | 27.078 |
| 64 | Batch | 134.867 → 87.334 | 156.679 → 109.197 | 27.078 |
| 1,024 | Full image | 293.951 → 200.369 | 31.822 → 31.570 | 36.766 |
| 1,024 | Journal | 245.756 → 157.101 | 277.921 → 190.568 | 53.812 |
| 1,024 | Batch | 243.777 → 156.695 | 274.771 → 187.484 | 53.812 |

Complete image and journal bytes, hashes, writes, syncs and renames are identical. Peak RSS
shows no material change. These are local observations; the final interleaved confirmation follows.

The final interleaved A/B run used the two frozen checked binaries, identical native object
code/provider pins and fixture identities, three warmups and ten measured rounds per
mode/size/binary (156 fresh consumers). The existing resource/work observer was used because
`hyperfine` was unavailable. Raw evidence is in `build/storage-db5-span-ab-final/`.

| Value bytes | Mode | Update ms baseline → candidate | Reopen ms baseline → candidate |
| ---: | --- | ---: | ---: |
| 64 | Full image | 172.231 → 119.017 | 19.957 → 19.814 |
| 64 | Journal | 138.768 → 89.434 | 159.482 → 108.637 |
| 64 | Batch | 137.178 → 86.884 | 157.727 → 107.120 |
| 1,024 | Full image | 286.803 → 197.627 | 31.322 → 31.696 |
| 1,024 | Journal | 246.640 → 156.626 | 274.212 → 192.964 |
| 1,024 | Batch | 250.942 → 152.114 | 277.317 → 184.766 |

Medians improve across the affected paths in both panels; individual samples include scheduling
outliers. Full-image reopen does not call the changed edit loop and remains comparable. This
supports a local fixture-specific improvement, without a general speedup or cold-cache claim.
Post-change 1,024-byte replay profiles show 139/123/140 samples in successor hashing, with
6/6/2 directly in the copying branch, versus the earlier 84/87/90 direct edit-loop samples.
Hash compression now dominates. Sampling windows differ; counts are not instruction ratios.

Seven native suites pass: incremental updates, atomic batches, deltas, replay, streaming reopen,
explicit repair and journal batches. Each retains its 1,000-cycle equal-occupancy ARC witness.
The update suite also passes AddressSanitizer with unchanged checked ARC/LTO options. Full
formatting, verification inventory and whitespace checks pass. No public result/API or on-disk
schema changed; existing refusal, repair and immutable-reader contracts remain applicable.

The next measured-memory hypothesis is to end private checkpoint extraction/result lifetimes
before replay starts advancing. The current reopen scopes appear to retain the initial checkpoint
while later successor images are reconstructed. Confirm the effect using the same matched panel
and preserve every failure/EOF/held-inode check before accepting a change.
