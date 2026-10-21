# Retained local download ancestry

Scope: opt-in capture of the selected immutable rolling history before explicit older files.
Pinned protocol behavior remains Gray Paper 0.8.0 and the existing report admission contract;
this changes context acquisition only, with no protocol or upstream pin changes.

The capture excludes the selected head, emits all retained parents newest-first, and appends
explicit older headers in caller order. It checks exact local parent identity and increasing slots.
Separated finality is never searched to bridge eviction. Count, per-header bytes and aggregate
bytes apply to the combined result; failure exposes no partial prefix. Ordinary report admission
still checks the complete supplied lineage, including explicit suffix links.

Completion covers capture boundaries/ownership, CLI activation, real download/restart
behavior and explicit suffix refusal. Remote acquisition and unbounded history remain outside scope.

## Command and lifetime contract

`--download-local-ancestors` is unique, valueless, state-enabled and download-only;
failed/default parses disable it. The default explicit-file behavior is unchanged.
External files are captured before Services. Local headers are captured from the
actual restored view after startup and before outgoing transport; no whole-view or
complete-map alias survives into the exclusive preparation worker lease. Capture
returns independent sequence storage retaining immutable sealed headers only.

For L local parents, A files and N requested children, reserve L+A+N−1 older
inputs and L+A+N report-validation headers. Combined initial capture failure
returns InvalidAncestors; insufficient future count reservation returns InvalidPolicy.
Parent-inclusive report bytes remain checked by the existing preflight. Subsequent
headers are carried by the existing bounded command, including confirmed partial
progress. A fresh disk seed can already exist before local admission refuses.
No storage, trie, Services, finality or checkpoint trust interface changes are required.

## Focused local evidence

- `application_local_ancestors`: genuine composed eight-child history, exact local
  order, selected-head exclusion, evicted separate finality, explicit older suffix,
  exact count/byte fits, one-short refusals, invalid owners, one-head/default view,
  independent returned sequence storage and 1,000 ARC capture/refusal cycles.
- `application_ancestor_options`: opt-in/default, duplicates, unrelated commands,
  disabled state and atomic parse reset.
- `application_download_progress`: unchanged default real TLS sequencing, deadlines,
  per-child fallback and partial progress.
- `application_download_disk_progress`: real retained local restart, zero-request
  count/byte/future-count refusals with byte-identical existing journal, exact-byte
  successful request, subsequent multi-child progress, complete-map restart parity
  and unchanged explicit finality.
- `application_download_startup`: genuine report/lookup success with the required
  explicit suffix when local capture is empty; omitted lookup and altered seal
  remain refusals, malformed suffixed files refuse before transport; ARC unchanged.
- Existing executable sequence workload adds a resumed case: independent native
  witness seeds one genuine durable child and explicit finality, the production
  executable requests two additional children using local capture, and the witness
  checks exact changing-parent requests and all complete restored maps/finality.
  Existing success/replay/timeout cases remain required.

M1 framing is complete. Full state serialization and whole-block JAM/STF parity
remain open. [Remote ancestor acquisition](application-remote-ancestors.md) now has
its own bounded interface. History beyond bounded retention, fork choice, discovery
and production node lifecycle remain separate work. This is
focused local evidence, not exact-head Linux CI or whole-suite parity.
