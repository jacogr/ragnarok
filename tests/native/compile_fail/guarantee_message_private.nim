## Fixed signing bytes stay private on every result alternative.
import ../../../src/crypto/[primitives, guarantee]
let parsed = default(GuaranteeMessageResult)
discard parsed.completed
