## Private discriminators cannot be supplied through an external variant constructor.
import ../../../src/codec/[c2_records, composite]
discard AccumulationValue(inputKind: AccumulationKind.Transfer)
