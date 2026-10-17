## Only the read-only reason accessor exposes result status.
import ../../../src/crypto/[primitives, guarantee]
let parsed = default(GuaranteeMessageResult)
discard parsed.status
