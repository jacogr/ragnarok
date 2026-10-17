## Safe callers cannot bypass private package/import state through packageIdentity.
import ../../../src/codec/[work_package, work_report]
var value = default(ImportReference)
discard value.packageIdentity
