from std.collections import Array, Span
from codec.types import CheckedResult, Failure
from .primitives import blake2b256, Blake2bHash


# GP v0.7.1 guarantorsig message, distinct from signatures and raw report hashes.
@fieldwise_init
struct GuaranteeMessage(Copyable, Movable):
    var bytes: Array[UInt8, 46]


# Hash exactly canonical report bytes and prepend ASCII $jam_guarantee; callers validate/serialize reports.
# This composition does not check validator assignments, timeslots or the unresolved Ed25519 acceptance policy.
def guarantee_message(
    canonical_report: Span[mut=False, UInt8, _]
) -> CheckedResult[GuaranteeMessage]:
    comptime Result = CheckedResult[GuaranteeMessage]
    var hashed = blake2b256(canonical_report)
    # Failed provider calls expose no default or partial signing message.
    if hashed.isa[Failure]():
        return Result(hashed[Failure].copy())
    var message = Array[UInt8, 46](fill=0)
    var domain = String("$jam_guarantee")
    var bytes = domain.as_bytes()
    # The literal domain includes the leading dollar sign and no terminator.
    for i in range(14):
        message[i] = bytes[i]
    # Hash bytes retain their exact identity order, without a second hash or timeslot suffix.
    for i in range(32):
        message[14 + i] = hashed[Blake2bHash].bytes[i]
    return Result(GuaranteeMessage(message^))
