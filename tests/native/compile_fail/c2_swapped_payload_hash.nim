## Operand payload hashes are not interchangeable with package identity hashes.
import ../../../src/[c2_records, work_report]
let value = AccumulationOperand(payloadHash: PackageHash())
discard value
