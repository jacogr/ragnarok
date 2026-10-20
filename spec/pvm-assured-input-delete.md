# Input-count-controlled guest storage deletion

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, input-list
fetch, register arithmetic/conditional assignment and empty-value storage deletion;
vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author a FetchDelete guest before computation/signing. Fetch one count byte from
selector14, load it with a real PVM memory instruction, and derive value length
(2-count)*3 using neg_add_imm_64 and mul_imm_64. Historical count1 writes three
bytes[1,22,23]; genuine assured count2 selects length0 and deletes that exact key.
Real cmov_nz_imm selects the RW value pointer only for nonempty values; deletion
retains an invalid maximum pointer, which the empty read must ignore.

No report, memory, count, terminal or completed source is patched. Original
funding50, capture3, gas10000 then20000 and all protocol parameters remain. A
storage-key deletion is not account ejection: preserve the account/balance/code,
set storage footprint/item count to0 and retain one deletion-provenance key with
zero copied value bytes. Distinguish MissingKey from a present empty value.

Independent gas oracle: list request1 costs288 and key1/value0 write2446. The same
syntactic instruction block costs at most997: successor gas>2734and<=3731.
The original three-byte write costs one more gas, so original actual gas must equal
successor actual gas plus1. The guest has17 instructions/2 hosts inside20/4 bounds.

Completion: actual original creation and successor deletion, full metadata,
report counts/history/activity/parameters/state/view identity and finality. A
one-byte copy ceiling and zero final-value byte budget must still permit deletion;
zero key/provenance budgets must refuse. Original aliases stay unchanged. Run1000
full guest/composition/publication ownership cycles and all affected older suites,
source-owned inventory/tooling and formatting. Production APIs remain unchanged.

Next: exercise input-dependent control flow and exceptional state selection.
M1 framing complete; full serialization, whole-block parity and full chainspec
equivalence remain open.

Observed local native evidence: the genuine single-input guest creates[1,22,23]
with footprint38/item1. The two-input guest derives value length0, retains its
invalid maximum value pointer, and actuallyHalt/Regular deletes the existing key.
The result is MissingKey with footprint0/items0; account, balance50 and code remain.
One proof key and zero copied final bytes are retained; deletedAccounts remains0.
Actual successor gas is greater than2734 and no more than3731; the original
three-byte write consumes exactly one more gas with the same instruction block.

Copy ceiling1 and final-value budget0 succeed together. Zero final key budget
preserves RunnerFailure/CompletionFailure/BatchFailure/LimitExceeded; zero captured
key provenance preserves UnsupportedAccountEffects. Copy ceiling0 refuses the
real one-byte input-count fetch with DispatchFailure/LimitExceeded. Canonical
parent/view remain exact after every refusal. Successful composition/publication
keeps absence, surviving account timestamp3, history3, activity reports2/
refinement0/actualgas, all29 parameters and finality1; old aliases retain the key.

One thousand full deletion executions/compositions/publications retain
753424/753424 occupied bytes. All six affected older suites pass again at1000
cycles: tail753792, ranges938352, list1459632, individual inputs1406672,
storage2933856 and outcomes3162032 bytes unchanged each. Only the shared guest
factory changes among3452 predecessor inputs;3451 remain identical and production
code is unchanged. Semantic checks,35 tooling tests, inventory194 families/2436
probes/271 native suites, and pinned formatting2337 Nim files plus Rust pass.
Local macOS checked-release evidence; remote CI was not requested.
