## Safe callers cannot bypass private package/import state through status.
import ../../../src/codec/[work_package, work_report]
var value = default(PackageResult[int])
discard PackageResult[int](status: PackageError.None)
