## Safe callers cannot bypass private package/import state through referenceKind.
import ../../../src/codec/[work_package, work_report]
var value = default(ImportReference)
value.referenceKind = ImportKind.Package
