## Service dictionary ordinals cannot select core positions.
import ../../../src/state_statistics
let owner = default(ActivitySnapshot)
discard coreActivityAt(owner, StatisticsServiceIndex(0))
