# Invocation-local service lifecycle order

Scope: pinned GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, existing successful new/eject effects. No host behavior, state/wire encoding, root or pin changes.

Creation and ejection facts now carry a nominal shared captured-operation ordinal. Each successful captured operation takes the sum of the two retained array lengths; each native length is at most signed `high(int)`, so their unsigned sum fits before arithmetic. Existing independent fact capacities and native descriptor bounds still apply before candidate account hashing/publication. No second event array or mutable effect graph is introduced.

Complete lifecycle order requires both creation and ejection tracing enabled. An ordinal from one enabled array alone is only captured order, not proof that every lifecycle operation was recorded. Future consumers must check both original capture policies. Ordinals are local to one invocation lineage; they grant no ordering between parallel invocations or separate service generations by themselves.

Facts publish only with the successful immutable account successor. Failed operations retain previous counts; regular/checkpoint versions share immutable facts, so terminal selection restores the exact captured prefix and its next ordinal. Copies are detached observations, not authority to submit replacement provenance.

Completion witnesses use actual native host execution: creation before ejection and ejection before creation, two successful ejections, same-ID ejection/recreation, ordinary panic and checkpoint selection, detached observation mutation, existing count limits, independent full roots, and the existing retained-owner/ARC cycles in the created/deleted account suites. The namespace consumer admits only an originally empty service with a unique same-invocation ejection-before-creation pair and a present actual replacement. Complete current/full-map/raw-key qualification still follows. Nonempty or ambiguous replacement generations remain refused. Genuine complete signed candidates cover halt, panic and checkpoint selection of the replacement and its code request.
