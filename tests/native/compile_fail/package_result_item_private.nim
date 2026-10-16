## Safe callers cannot bypass private package/import state through completed.
import ../../../src/codec/[work_package, work_report]
var value = default(PackageResult[ItemRead])
discard value.completed
