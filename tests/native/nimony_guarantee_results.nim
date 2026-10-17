## Guarantee result contracts reject default/failed values for every public operation family.
import std/[cmdline, syncio]
import ../../src/codec/[guarantees, bounded, assurances, work_report]

let useDefault = paramStr(2) == "default"
let config = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
    maxBytes: ByteLimit(1024))
let empty: seq[byte] = @[]
let missing = default(OwnedGuarantees)
let source = default(Guarantee)
var destination = newSeq[byte](0)
let multiple = if useDefault: default(GuaranteeResult[GuaranteesRead]) else: decodeGuarantees(empty, config)
let single = if useDefault: default(GuaranteeResult[GuaranteeRead]) else: decodeGuarantee(empty, config)
let selected = if useDefault: default(GuaranteeResult[Guarantee]) else: guaranteeAt(missing, 0)
let encoded = if useDefault: default(GuaranteeResult[int]) else: encodeGuarantees([source], config, destination)
let owned = if useDefault: default(GuaranteeResult[int]) else: encodeOwnedGuarantees(missing, destination)
let measured = if useDefault: default(GuaranteeResult[int]) else: measureGuarantee(source, config)
let bytes = if useDefault: default(GuaranteeResult[seq[byte]]) else: encodeGuaranteeValue(source, config)
let scanned = if useDefault: default(GuaranteeResult[tuple[count,
    consumed: int]]) else: inspectGuarantees(empty, config)
let record = if useDefault: default(GuaranteeResult[tuple[core: CoreIndex,
    consumed: int]]) else: inspectGuarantee(empty, config)
case paramStr(1)
of "owner": echo ord(guaranteeAt(multiple.value.owner, 0).error) # No fabricated validated parent.
of "count": echo multiple.value.count # No initialized-record count after failure.
of "consumed": echo multiple.value.consumed # No cursor progress after failure.
of "single-value": echo uint32(single.value.value.slot) # No fabricated standalone wrapper.
of "single-consumed": echo single.value.consumed # No standalone cursor progress.
of "selected": echo uint32(selected.value.slot) # No default selected record.
of "encoded": echo encoded.value # No byte count from invalid source records.
of "owned": echo owned.value # No byte count from a missing parent.
of "measured": echo measured.value # No extent from an invalid child handle.
of "bytes": echo bytes.value.len # No fresh empty byte result after failed preflight.
of "inspect-count": echo scanned.value.count # No extrinsic scan count after failure.
of "inspect-consumed": echo scanned.value.consumed # No extrinsic scan progress after failure.
of "record-core": echo uint64(record.value.core) # No nominal core from invalid standalone input.
of "record-consumed": echo record.value.consumed # No standalone scan progress after failure.
of "factory":
  # An explicit failure constructor cannot tag a missing value as success.
  let reason = if paramStr(2) == "none": GuaranteeError.None else: GuaranteeError.InvalidOwner
  echo ord(guaranteeFailure[int](reason).error)
else: quit 2 # Unknown probes cannot count as contract rejections.
