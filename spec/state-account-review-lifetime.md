# Detached account review and branch lifetime evidence

This ownership evidence increment exercises existing immutable complete snapshots
and account review/checkpoint consumers without changing their public surface.
A uniquely owned caller transport is overwritten and freed after synchronous
restoration. Review handles are copied and dropped in opposite order; fixed copied
observations and copied payload bytes are mutated independently. The source must
remain correct after all review/component handles retire.

An independently mutable in-memory fork then publishes changed account metadata;
the retained original root, payload and unchanged checkpoint encoding must remain
exact. Every complete decode/drop/fork graph retires within one activation. Fresh
1,000-cycle warmed ARC measurement requires identical live allocation before and
after. No storage API/format, worker lease, canonical adoption, root policy or
protocol rule changes occur. Application callers retain the documented canonical
worker ARC exclusion obligations; this test uses independent synchronous graphs.
Run `make unit SUITE=state_account_review_lifetime`.

Observed locally: selected native suite, inventory and pinned formatting passed. Existing production contract/privacy controls are unchanged. 1,000 ARC cycles retained 120,928 bytes before and after.
