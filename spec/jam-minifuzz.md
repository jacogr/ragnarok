# Pinned upstream minifuzz interoperability

Scope: execute the unchanged minifuzz script from conformance commit
`acd4b2da310ff25226c4d41b918712578483fd2c` against actual `serve-fuzz`
with independently calculated whole-map traces under GP
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. GP, VRF, vectors, historical
fixtures and the conformance pin remain unchanged. This is fixed-trace upstream
tool interoperability, not a generated campaign or cross-client STF comparison.

`jam-minifuzz-pins.json` binds upstream jam-types-py0.8 source, its codec and
pure-Python dependency wheels by exact revisions/archive hashes. Preparation runs
no upstream installer, package build or global pip operation. Pristine bounded
source trees and exact wheels enter only the subprocess PYTHONPATH; `python -S`
and disabled bytecode/user-site imports isolate the upstream process. Warm source
changes, injected files, unsafe archive members or checksum changes refuse setup.
Make's `minifuzz-tools` and the owning E2E setup provide these dependencies.

Independent guest, sibling, mismatched-clock seed and checkpoint references author
35 sessions,130 signed imports and415 complete request/reply pairs before startup.
All full State responses, roots, exact headers, original-last sibling maps and
retained seeds remain independently calculated. A bounded socket proxy observes
the real minifuzz process and forwards exact bytes to the actual native target.
Every planned request/reply must match, with complete frame/process termination.
No target response constructs an expected file or repairs a later input.

The upstream runner can exit0 after a comparison mismatch. A real negative control
corrupts its last returned State value, requires upstream's decoded mismatch and
zero status, and requires the strict wrapper to fail. CI requires every exchange
plus this control; outer success flags or upstream exit status alone cannot pass.
The source-owned E2E workload and Fuzz / JAM entry include this lane. Logs, trace
pairs, independent hashes and observed frame hashes remain under ignored build/.
Compatible live-engine generated campaign validation remains pending.
