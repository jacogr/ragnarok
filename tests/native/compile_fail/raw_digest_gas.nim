# Deliberately reject an interchangeable raw/wrong-domain digest field at compile time.
import ../../../src/codec/work_digest
var wrong: uint64
var value: WorkDigest
value.accumulateGas = wrong
