## Recent-block positions cannot silently become MMR belt positions.
import ../../../src/state_history
var owner: HistorySnapshot
var index: HistoryBlockIndex
let peak = historyPeakAt(owner, index)
discard peak
