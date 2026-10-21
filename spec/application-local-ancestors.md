# Retained local download ancestry

Scope: opt-in capture of the selected immutable rolling history before explicit older files.
Pinned protocol behavior remains Gray Paper 0.8.0 and the existing report admission contract;
this changes context acquisition only, with no protocol or upstream pin changes.

The capture excludes the selected head, emits all retained parents newest-first, and appends
explicit older headers in caller order. It checks exact local parent identity and increasing slots.
Separated finality is never searched to bridge eviction. Count, per-header bytes and aggregate
bytes apply to the combined result; failure exposes no partial prefix. Ordinary report admission
still checks the complete supplied lineage, including explicit suffix links.

Completion evidence will cover capture boundaries/ownership, CLI activation, real download/restart
behavior and explicit suffix refusal. Remote acquisition and unbounded history remain outside scope.
