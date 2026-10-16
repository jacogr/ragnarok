import ../../../src/codec/[guarantees, work_report]
# Lookup-anchor timeslots cannot silently become guarantee evaluation timeslots.
let wrong = Guarantee(slot: LookupSlot(1))
discard wrong
