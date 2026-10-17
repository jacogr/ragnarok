# Deliberately reject an interchangeable raw/wrong-domain digest field at compile time.
import ../../../src/codec/work_digest
var wrong = default(PayloadHash)
var value = default(WorkDigest)
value.codeHash = wrong
