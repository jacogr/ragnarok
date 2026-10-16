## Scalar owners do not expose native pointers or mutable ARC storage.
import ../../../src/bandersnatch/bandersnatch
let key = default(BsKey)
discard key.state
