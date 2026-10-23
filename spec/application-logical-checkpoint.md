# Logical source checkpoint capture

`captureLogicalCheckpoint` selects only the existing genuine producer retained by a completed
CurrentLogicalState, then delegates unchanged full-checkpoint capture under an explicit byte
limit. Its private guarded result preserves original checkpoint causes. Exact prior and posterior
roots and finality presence/absence retain their existing meanings; this supplies no independent
root trust or installation. Returned capsules retain original source ownership and export detached
mutable byte copies under separate budgets. Native scope-retirement, caller tampering and exact/
one-short byte policies verify the boundary. All operations run outside native ARC graph leases.

Services exposes explicit retained-source capture under preparation/proof/publication exclusion.
It does not select a trusted root or install state. The managed native witness checks genuine
collection, exact retained physical source, NoFinality and detached bytes after joined shutdown.
