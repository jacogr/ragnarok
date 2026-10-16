## Segment commitments cannot silently become dictionary package identities.
import ../../../src/state_history
var root: SegmentRoot
let pair = ReportedPackage(package: root)
discard pair
