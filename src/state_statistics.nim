## GP 0.8.0 T chapter 13 and statistics activityspec: retained structural statistics, not updates.
import ./[natural, bounded, composite, assurances, state_layout, state_trie]
export ServiceIndex, CoreCount, ValidatorCount

type
  ## Current and previous epoch populations are separately configured and need not match after resizing.
  StatisticsEpoch* {.pure.} = enum
    Current, Previous
  ## Six validator counters follow the exact activityspec tuple order, all encoded E4.
  ValidatorMeasure* {.pure.} = enum
    Blocks, Tickets, PreimageCount, PreimageBytes, Guarantees, Assurances
  ## Fixed E4 validator counter; a natural gas allowance cannot be assigned without conversion.
  ValidatorCounter* = distinct uint32
  ## Core non-gas measures precede the final gas field in their normative order.
  CoreMeasure* {.pure.} = enum
    DataAvailabilityLoad, Popularity, Imports, ExtrinsicCount, ExtrinsicBytes, Exports, BundleBytes
  ## Service non-gas fields retain their named tuple positions; gas fields remain separate nominal values.
  ServiceMeasure* {.pure.} = enum
    ProvisionCount, ProvisionBytes, RefinementCount, Imports, ExtrinsicCount, ExtrinsicBytes,
    Exports, AccumulationCount, TransferCount
  ## Natural statistic fields support the entire canonical unsigned 64-bit encoding domain.
  ActivityNatural* = distinct uint64
  ## Gas statistics cannot accidentally substitute for natural counts or E4 validator counters.
  ActivityGas* = distinct uint64
  ## Every validator record is a fixed independent copy, with no nested mutable storage.
  ValidatorActivity* = array[ValidatorMeasure, ValidatorCounter]
  ## Seven natural core measures and final natural gas usage form one fixed eight-field tuple.
  CoreActivity* = object
    counters*: array[CoreMeasure, ActivityNatural]
    gas*: ActivityGas
  ## Eleven natural service fields include provision/refinement and three accumulation statistics.
  ServiceActivity* = object
    counters*: array[ServiceMeasure, ActivityNatural]
    refinementGas*, accumulationGas*: ActivityGas
  ## Service statistics dictionary entries retain the numeric service ID beside its complete fixed tuple.
  ServiceStatisticsEntry* = object
    service*: ServiceIndex
    statistics*: ServiceActivity
  ## Validator/core positions and service dictionary ordinals have independent nominal domains.
  StatisticsValidatorIndex* = distinct uint64
  StatisticsCoreIndex* = distinct uint64
  StatisticsServiceIndex* = distinct uint64
  ## Stable synchronous source; array shapes/order must already agree with the supplied profile.
  ActivityState* = object
    validators*: array[StatisticsEpoch, seq[ValidatorActivity]]
    cores*: seq[CoreActivity]
    services*: seq[ServiceStatisticsEntry]
  ## Both roster populations are explicit; item and whole-parent byte ceilings independently bound resources.
  ActivityConfig* = object
    cores*: CoreCount
    current*, previous*: ValidatorCount
    maxServices*: ElementLimit
    maxBytes*: ByteLimit
  ## Default and failures carry only reasons, without values, owner handles or parser progress.
  ActivityError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical, LimitExceeded,
    LengthOverflow, InvalidService, InvalidOwner, InvalidIndex
  ## Only complete success exposes an application payload.
  ActivityResult*[T] = object
    case error*: ActivityError
    of ActivityError.None:
      value*: T # Success must be selected before any payload access.
    else:
      discard   # Default/failed alternatives cannot masquerade as empty statistics.
  ## Acyclic private ARC storage owns independent fixed records, without caller-array aliases.
  ActivityData = ref object
    state: ActivityState
  ## Value handles retain shared immutable private storage; replacement cannot mutate other copies.
  ActivitySnapshot* = object
    data: ActivityData
  ## Prefix success binds its retained snapshot to the exact complete consumed extent.
  ActivityRead* = object
    snapshot*: ActivitySnapshot
    consumed*: int
  ## Copied cardinalities expose no mutable validator/core/service arrays.
  ActivityInfo* = object
    validators*: array[StatisticsEpoch, int]
    cores*, services*: int
  ## Local proof holds only offsets/counts and never escapes as detached input spans.
  Layout = object
    starts: array[StatisticsEpoch, int]
    coreStart, serviceStart, services, consumed: int

## Validate both independent roster domains before core/count conversions or input access.
proc validate(config: ActivityConfig): ActivityError =
  if not validConfig(AssuranceConfig(cores: config.cores, validators: config.current)) or
      not validConfig(AssuranceConfig(cores: config.cores, validators: config.previous)):
    return ActivityError.InvalidConfig # Preserve the existing 2..341 core and 3c validator profile domain.
  ActivityError.None

## Select a configured roster population without requiring the previous roster to equal the current one.
proc population(config: ActivityConfig, epoch: StatisticsEpoch): int =
  if epoch == StatisticsEpoch.Current: int(uint64(
      config.current)) # Current roster fixes the first sequence count.
  else: int(uint64(config.previous)) # A resized epoch retains its older independent count.

## Charge nonnegative parent bytes before arithmetic and before reads/allocation/commit.
proc grow(cursor: var int, amount: int, config: ActivityConfig): ActivityError =
  if amount > high(int)-cursor: return ActivityError.LengthOverflow # Never overflow native extent arithmetic.
  cursor += amount
  if uint64(cursor) > uint64(config.maxBytes): return ActivityError.LimitExceeded # All count/scalar bytes share one budget.
  ActivityError.None

## Bound service traversal and eventual typed storage before a hostile count can authorize allocation.
proc serviceCount(count: uint64, config: ActivityConfig): ActivityError =
  if count > uint64(config.maxServices): return ActivityError.LimitExceeded # Caller item policy bounds dictionary work first.
  if count > uint64(high(int) div sizeof(ServiceStatisticsEntry)):
    return ActivityError.LengthOverflow # Typed fixed records must fit native addressing.
  ActivityError.None

## Read a single canonical natural using a private cursor; failure never exports partial progress.
proc readNatural(input: openArray[byte], cursor: var int, config: ActivityConfig): ActivityResult[uint64] =
  let parsed = natural.decode(input.toOpenArray(cursor, input.len-1))
  if not parsed.ok:
    if parsed.error == DecodeError.truncated:
      return ActivityResult[uint64](error: ActivityError.Truncated) # Missing count/key/measure is incomplete framing.
    else:
      return ActivityResult[uint64](error: ActivityError.NonCanonical) # Reject alternate encodings of a complete scalar.
  let error = grow(cursor, parsed.consumed, config)
  if error != ActivityError.None: return ActivityResult[uint64](
      error: error) # Complete scalars still consume policy.
  ActivityResult[uint64](error: ActivityError.None, value: uint64(parsed.value))

## Fixed local tuples validate all natural children without heap allocation or externally reusable spans.
proc readFields[N: static int](input: openArray[byte], cursor: var int,
    config: ActivityConfig): ActivityResult[array[N, uint64]] =
  var fields: array[N, uint64]
  # Tuple arity is a schema constant; no input count controls this local array size.
  for i in 0..<N:
    let parsed = readNatural(input, cursor, config)
    if parsed.error != ActivityError.None: return ActivityResult[array[N, uint64]](
        error: parsed.error) # Late fields reject the tuple.
    fields[i] = parsed.value
  ActivityResult[array[N, uint64]](error: ActivityError.None, value: fields)

## Preflight every component, including the last service field, before capturing any owner storage.
proc scan(input: openArray[byte], config: ActivityConfig): ActivityResult[Layout] =
  let valid = validate(config)
  if valid != ActivityError.None: return ActivityResult[Layout](
      error: valid) # Invalid profile cannot authorize reads.
  var layout: Layout
  var cursor = 0
  # Each epoch has its own natural count followed by six E4 fields per record, not natural counters.
  for epoch in StatisticsEpoch:
    let count = readNatural(input, cursor, config)
    if count.error != ActivityError.None: return ActivityResult[Layout](
        error: count.error) # Canonical count required before shape check.
    if count.value != uint64(population(config, epoch)):
      return ActivityResult[Layout](error: ActivityError.InvalidCount) # Counts must match their corresponding supplied roster.
    layout.starts[epoch] = cursor
    let error = grow(cursor, int(count.value)*24, config)
    if error != ActivityError.None: return ActivityResult[Layout](
        error: error) # Profile bounds prove multiplication safe.
    if cursor > input.len: return ActivityResult[Layout](
        error: ActivityError.Truncated) # Fixed counters must all be present.
  layout.coreStart = cursor
  # Core cardinality is fixed by profile: no count discriminator appears here.
  for i in 0..<int(uint64(config.cores)):
    let fields = readFields[8](input, cursor, config)
    if fields.error != ActivityError.None: return ActivityResult[Layout](
        error: fields.error) # A late core rejects the complete parent.
  let count = readNatural(input, cursor, config)
  if count.error != ActivityError.None: return ActivityResult[Layout](
      error: count.error) # Empty dictionary still requires its count.
  let error = serviceCount(count.value, config)
  if error != ActivityError.None: return ActivityResult[Layout](
      error: error) # Check count/native storage before pair traversal.
  layout.services = int(count.value)
  layout.serviceStart = cursor
  var previous = 0'u64
  # Numeric ascending service keys are canonical; values retain tuple order and need not be sorted.
  for i in 0..<layout.services:
    let key = readNatural(input, cursor, config)
    if key.error != ActivityError.None: return ActivityResult[Layout](
        error: key.error) # Missing/overlong key rejects all earlier data.
    if key.value > uint64(high(uint32)): return ActivityResult[Layout](
        error: ActivityError.InvalidService) # Never narrow an invalid service ID.
    if i > 0 and key.value <= previous:
      return ActivityResult[Layout](error: ActivityError.NonCanonical) # Equal and descending numeric IDs are invalid.
    previous = key.value
    let fields = readFields[11](input, cursor, config)
    if fields.error != ActivityError.None: return ActivityResult[Layout](
        error: fields.error) # No partial record on late gas failure.
  layout.consumed = cursor
  ActivityResult[Layout](error: ActivityError.None, value: layout)

## Convert a typed core record to the exact eight natural wire positions without exposing retained arrays.
proc coreFields(value: CoreActivity): array[8, uint64] =
  # Seven named non-gas counters precede the final gas statistic.
  for measure in CoreMeasure: result[ord(measure)] = uint64(value.counters[measure])
  result[7] = uint64(value.gas)

## Convert typed service fields to provision/refinement/import/extrinsic/export/accumulation wire order.
proc serviceFields(value: ServiceActivity): array[11, uint64] =
  [uint64(value.counters[ServiceMeasure.ProvisionCount]), uint64(value.counters[
      ServiceMeasure.ProvisionBytes]),
    uint64(value.counters[ServiceMeasure.RefinementCount]), uint64(value.refinementGas),
    uint64(value.counters[ServiceMeasure.Imports]), uint64(value.counters[
        ServiceMeasure.ExtrinsicCount]),
    uint64(value.counters[ServiceMeasure.ExtrinsicBytes]), uint64(value.counters[
        ServiceMeasure.Exports]),
    uint64(value.counters[ServiceMeasure.AccumulationCount]), uint64(value.counters[
        ServiceMeasure.TransferCount]),
    uint64(value.accumulationGas)]

## Capture a complete preflighted component into independent fixed typed arrays with an immutable owner.
proc decodeActivityState*(input: openArray[byte], config: ActivityConfig): ActivityResult[ActivityRead] =
  let checked = scan(input, config)
  if checked.error != ActivityError.None: return ActivityResult[ActivityRead](
      error: checked.error) # No earlier owner/progress after failure.
  let layout = checked.value
  let data = ActivityData()
  # Both roster arrays own copied E4 values and preserve validator-position order.
  for epoch in StatisticsEpoch:
    data.state.validators[epoch] = newSeq[ValidatorActivity](population(config, epoch))
    var cursor = layout.starts[epoch]
    for i in 0..<data.state.validators[epoch].len:
      for measure in ValidatorMeasure:
        var value = 0'u32
        for j in 0..<4: value = value or (uint32(input[cursor+j]) shl (j*8)) # Explicit E4 little-endian copy.
        data.state.validators[epoch][i][measure] = ValidatorCounter(value)
        cursor += 4
  data.state.cores = newSeq[CoreActivity](int(uint64(config.cores)))
  var cursor = layout.coreStart
  # Read only proved tuples; immutable capture occurs after the whole parent is known valid.
  for i in 0..<data.state.cores.len:
    let fields = readFields[8](input, cursor, config).value
    for measure in CoreMeasure: data.state.cores[i].counters[measure] = ActivityNatural(fields[ord(
        measure)]) # Named natural domains.
    data.state.cores[i].gas = ActivityGas(fields[7])
  data.state.services = newSeq[ServiceStatisticsEntry](layout.services)
  cursor = layout.serviceStart
  # Preserve key/value pairing with explicit gaps for the two gas fields.
  for i in 0..<layout.services:
    let key = readNatural(input, cursor, config).value
    let fields = readFields[11](input, cursor, config).value
    var record = ServiceStatisticsEntry(service: ServiceIndex(key))
    for measure in ServiceMeasure:
      let position = if ord(measure) < 3: ord(measure) else: ord(
          measure)+1 # Refinement gas occupies wire position 3.
      record.statistics.counters[measure] = ActivityNatural(fields[position])
    record.statistics.refinementGas = ActivityGas(fields[3])
    record.statistics.accumulationGas = ActivityGas(fields[10])
    data.state.services[i] = record
  ActivityResult[ActivityRead](error: ActivityError.None,
    value: ActivityRead(snapshot: ActivitySnapshot(data: data), consumed: layout.consumed))

## Commit a measured canonical natural after whole-source validation and destination sizing.
proc putNatural(value: uint64, output: var seq[byte], cursor: var int) =
  let encoded = natural.encode(JamNatural(value))
  # Exact preflight size includes every natural prefix and payload octet.
  for i in 0..<encoded.len:
    output[cursor] = encoded.bytes[i]
    inc cursor

## Validate exact source shape/order/extent before allocating independent C(13) output bytes.
proc activityStateEntry*(source: ActivityState, config: ActivityConfig): ActivityResult[StateEntry] =
  let valid = validate(config)
  if valid != ActivityError.None: return ActivityResult[StateEntry](
      error: valid) # Configuration precedes source traversal.
  var size = 0
  # Both variable epoch arrays must match their separate roster populations.
  for epoch in StatisticsEpoch:
    let count = source.validators[epoch].len
    if count != population(config, epoch): return ActivityResult[StateEntry](
        error: ActivityError.InvalidCount) # Never infer a roster from source count.
    let error = grow(size, natural.encode(JamNatural(count)).len+count*24, config)
    if error != ActivityError.None: return ActivityResult[StateEntry](
        error: error) # Proved profile count bounds native multiplication.
  if uint64(source.cores.len) != uint64(config.cores):
    return ActivityResult[StateEntry](error: ActivityError.InvalidCount) # Fixed core sequence has no outer count.
  let count = serviceCount(uint64(source.services.len), config)
  if count != ActivityError.None: return ActivityResult[StateEntry](
      error: count) # Item/storage policy precedes variable source traversal.
  # Size every natural core field before allocating any encoded parent bytes.
  for core in source.cores:
    for field in coreFields(core):
      let error = grow(size, natural.encode(JamNatural(field)).len, config)
      if error != ActivityError.None: return ActivityResult[StateEntry](
          error: error) # Gas and counters share byte policy.
  let prefix = grow(size, natural.encode(JamNatural(source.services.len)).len, config)
  if prefix != ActivityError.None: return ActivityResult[StateEntry](
      error: prefix) # Even zero services consume a count byte.
  # Service inputs must already have strictly increasing numeric IDs; do not sort or deduplicate silently.
  for i, record in source.services:
    if i > 0 and uint32(record.service) <= uint32(source.services[i-1].service):
      return ActivityResult[StateEntry](error: ActivityError.NonCanonical) # Late duplicate/disorder invalidates all output.
    let key = grow(size, natural.encode(JamNatural(uint32(record.service))).len, config)
    if key != ActivityError.None: return ActivityResult[StateEntry](error: key) # Natural key is not E4.
    for field in serviceFields(record.statistics):
      let error = grow(size, natural.encode(JamNatural(field)).len, config)
      if error != ActivityError.None: return ActivityResult[StateEntry](
          error: error) # Include the last accumulation gas field.
  var entry = StateEntry(key: chapterKey(StateChapter(13)), value: newSeq[byte](size))
  var cursor = 0
  # Commit count-prefixed E4 validator tuples in current/previous order.
  for epoch in StatisticsEpoch:
    putNatural(uint64(source.validators[epoch].len), entry.value, cursor)
    for record in source.validators[epoch]:
      for measure in ValidatorMeasure:
        for j in 0..<4:
          entry.value[cursor] = byte((uint32(record[measure]) shr (j*8)) and
              255) # All counters retain their four-byte width.
          inc cursor
  # Fixed core sequence and variable numeric service dictionary use ordinary natural fields.
  for core in source.cores:
    for field in coreFields(core): putNatural(field, entry.value, cursor) # No core-array count discriminator.
  putNatural(uint64(source.services.len), entry.value, cursor)
  for record in source.services:
    putNatural(uint32(record.service), entry.value, cursor)
    for field in serviceFields(record.statistics): putNatural(field, entry.value,
        cursor) # Tuple has fixed arity, without its own count.
  ActivityResult[StateEntry](error: ActivityError.None, value: entry)

## Return copied record counts without exposing any retained arrays.
proc activityInfo*(owner: ActivitySnapshot): ActivityResult[ActivityInfo] =
  if owner.data.isNil: return ActivityResult[ActivityInfo](
      error: ActivityError.InvalidOwner) # Default is not validated zero state.
  var info = ActivityInfo(cores: owner.data.state.cores.len,
      services: owner.data.state.services.len)
  for epoch in StatisticsEpoch: info.validators[epoch] = owner.data.state.validators[
      epoch].len # Preserve independent populations.
  ActivityResult[ActivityInfo](error: ActivityError.None, value: info)

## Copy a complete validator tuple selected by epoch and nominal validator position.
proc validatorActivityAt*(owner: ActivitySnapshot, epoch: StatisticsEpoch,
    index: StatisticsValidatorIndex): ActivityResult[ValidatorActivity] =
  if owner.data.isNil: return ActivityResult[ValidatorActivity](
      error: ActivityError.InvalidOwner) # Missing storage cannot return counters.
  if uint64(index) >= uint64(owner.data.state.validators[epoch].len):
    return ActivityResult[ValidatorActivity](error: ActivityError.InvalidIndex) # Bound before native narrowing and selection.
  ActivityResult[ValidatorActivity](error: ActivityError.None, value: owner.data.state.validators[
      epoch][int(uint64(index))])

## Copy one core's complete fixed tuple through its independently checked nominal position.
proc coreActivityAt*(owner: ActivitySnapshot, index: StatisticsCoreIndex): ActivityResult[CoreActivity] =
  if owner.data.isNil: return ActivityResult[CoreActivity](
      error: ActivityError.InvalidOwner) # No default counters after failure.
  if uint64(index) >= uint64(owner.data.state.cores.len):
    return ActivityResult[CoreActivity](error: ActivityError.InvalidIndex) # Core positions are unrelated to dictionary ordinals.
  ActivityResult[CoreActivity](error: ActivityError.None, value: owner.data.state.cores[int(uint64(index))])

## Copy one numeric key and full service tuple; the pair has no owner-dependent mutable storage.
proc serviceActivityAt*(owner: ActivitySnapshot, index: StatisticsServiceIndex): ActivityResult[
    ServiceStatisticsEntry] =
  if owner.data.isNil: return ActivityResult[ServiceStatisticsEntry](
      error: ActivityError.InvalidOwner) # No fabricated service pair.
  if uint64(index) >= uint64(owner.data.state.services.len):
    return ActivityResult[ServiceStatisticsEntry](
        error: ActivityError.InvalidIndex) # Check dictionary cardinality before access.
  ActivityResult[ServiceStatisticsEntry](error: ActivityError.None,
      value: owner.data.state.services[int(uint64(index))])
