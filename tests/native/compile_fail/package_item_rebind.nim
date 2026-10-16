## Safe callers cannot bypass private package/import state through index.
import ../../../src/codec/[work_package, work_report]
var value = default(OwnedWorkItem)
value.index = 0
