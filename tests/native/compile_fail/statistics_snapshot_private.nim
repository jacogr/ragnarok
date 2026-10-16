## Retained arrays remain private immutable storage.
import ../../../src/state_statistics
let owner = default(ActivitySnapshot)
discard owner.data
