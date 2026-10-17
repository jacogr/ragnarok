## Safe callers cannot bypass private package/import state through root.
import ../../../src/codec/[work_package, work_report]
var value = default(ImportReference)
value.root = SegmentRoot()
