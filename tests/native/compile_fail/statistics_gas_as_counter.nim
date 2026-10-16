## Gas cannot silently become a fixed E4 validator counter.
import ../../../src/codec/state_statistics
var record: ValidatorActivity
record[ValidatorMeasure.Blocks] = ActivityGas(1)
