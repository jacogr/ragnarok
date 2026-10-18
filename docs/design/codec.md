# Codecs and ownership

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

Codecs and consensus-facing types live in `src/codec/`. Protocol logic remains native Nim. Private,
acyclic ARC owners retain immutable wire snapshots; borrowed paths use explicit lifetime contracts
and caller-owned storage. Default/failed tagged results carry no values or progress metadata.
