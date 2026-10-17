## Safe callers cannot bypass private package/import state through error.
import ../../../src/codec/[work_package, work_report]
var value = default(PackageResult[int])
value.error = PackageError.None
