# Managed disk backend adoption

The maintainer authorized a fresh storage tranche after native stack516 merged, capped at twenty
open stacked PRs. Storage owns `FileRepository`, `DiskStateStore`, managed maintenance and focused
application backend wiring. State #5 continues independent local-ancestry work; shared app additions
must preserve its startup, download and checkpoint trust interfaces.

The first boundary keeps `FileRepository.opened` a scalar lifecycle observation for worker polling.
An explicit managed initializer takes a complete nonzero-generation seed, and explicit managed
open/recovery chooses the layout. Existing single-file entry points and bytes stay unchanged; no
path probing grants migration or checkpoint trust. The facade translates only actual guarded
managed results into its existing error domain. Composite native owners still require explicit
close, reject ARC copies and preserve held immutable views.

Initial completion checks: managed facade lifecycle/publication/retention and 1,000 ARC reopen
cycles, legacy file repository regression and actual composite owner copy rejection. Subsequent
layers add managed DiskStateStore creation/restoration, context/history, maintenance and worker
boundaries before opt-in application wiring. Complete maps, inherited ceilings, exact parent
identity, explicit IO uncertainty and external trust for checkpoint imports remain mandatory.
