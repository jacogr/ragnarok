## Token balance cannot silently accept gas units.
import ../../../src/state_accounts
let metadata = ServiceMetadata(balance: Gas(1))
discard metadata
