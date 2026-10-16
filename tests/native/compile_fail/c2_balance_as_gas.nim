## Balance and gas share a width but remain independent protocol units.
import ../../../src/c2_records
let value = DeferredTransfer(gas: TransferBalance(1))
discard value
