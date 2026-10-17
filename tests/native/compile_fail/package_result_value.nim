## Safe callers cannot bypass private package/import state through value.
import ../../../src/codec/[work_package, work_report]
var value = default(PackageResult[int])
value.value = 0
