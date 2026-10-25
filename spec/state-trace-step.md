# Published TraceStep binary composition

Authority: vectors `23061ae1f9b51171c01387e7dde0f15794c98e24`,
`traces/schema.asn` and `traces/convert.py`. A TraceStep concatenates RawState
pre-state, regular complete block, and RawState post-state, with no added wrapper,
magic or invented length fields.

`state/trace_step` composes the existing bounded RawState and owned block codecs.
Its private immutable owner retains each actual child, captured block configuration
and exact prefix extent. Default/failed alternatives contain no children or progress;
pre-state, block and post-state failures preserve their original typed reasons.
Raw state limits, structural block profile and aggregate byte ceiling are explicit
caller inputs, rather than inferred from a root or embedded in this wire format.
Count/length arithmetic remains bounded before narrowing, and detached copying
preflights the combined three-field extent before writing any output.

`newTraceStep` also composes already validated immutable children with a combined
extent bound. Getters retain their original child even after the enclosing owner
is released. This is schema/root validation only: a post-state is not certified as
that block's STF result, signatures are not verified, and no logical identities,
full Parameters, selected-parent or chain-installation authority are manufactured.
Those relationships belong to actual import/admission.

The independent corpus freezes264 cases before native execution:255 current-profile
signed transitions and three exact pinned published binary/JSON traces, plus six
typed field/root/truncation/ceiling refusals. For each accepted step, an independent
reference compares complete pre-state checkpoint, exact block bytes, complete
post-state checkpoint and the entire published binary file. Current-profile cases
include genuine allowances, gas eligibility, incarnation recreation/rebinding,
foreign debits and queued old reports. Published historical metadata remains opaque
and unchanged. A trailing field proves exact prefix capture.

Native ownership units mutate input and detached output, release enclosing owners,
recapture children, refuse every short output ceiling and incomplete children,
exercise invalid structural profiles and isolate each malformed state/block field.
Privacy compilation checks deny owner/result internals. Focused semantic/native/
reference checks, twice-idempotent pinned formatting and inventory cover completion.
Local checked ARC/Clang evidence remains separate from exact-head Linux CI.
Actual trace import, profile binding and external STF differential comparison remain
next; successful composition is not a transition-conformance claim.
