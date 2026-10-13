# Deliberately reject an interchangeable raw/wrong-domain digest field at compile time.
import ../../src/work_digest
var wrong: PayloadHash
var value: WorkDigest
value.codeHash = wrong
