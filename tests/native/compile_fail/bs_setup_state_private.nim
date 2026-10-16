## Setup owners do not expose native pointers or mutable ARC storage.
import ../../../src/bandersnatch/bandersnatch
let setup = default(BsSetup)
discard setup.state
