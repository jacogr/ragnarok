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
