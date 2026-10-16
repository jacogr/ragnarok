## Independent decimal-field source transport and copied-value observation for chapter 13.
import std/[os, strutils]
import ../../src/[state_statistics, state_trie, bounded]

## Preserve empty arrays and malformed empty wire without inventing protocol bytes.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty trusted token is not an encoded zero.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1])) # Parse complete literal octets.

## Observe exact serialized output including leading zeroes and count discriminators.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Empty observations retain their transport position.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii()) # Preserve all independently expected bytes.

## Decimal fields build typed sources independently of the production byte decoder.
proc numbers(text: string): seq[uint64] =
  if text == "-": return @[] # Empty source sequence is expressible for shape errors.
  for field in text.split(','): result.add(parseBiggestUInt(field)) # Preserve numeric order and duplicate keys.

## Map exact eight-field source rows to the typed core domains.
proc core(fields: openArray[uint64]): CoreActivity =
  doAssert fields.len == 8
  for measure in CoreMeasure: result.counters[measure] = ActivityNatural(fields[ord(
      measure)]) # Seven count fields precede gas.
  result.gas = ActivityGas(fields[7])

## Map complete service rows by named fields, including the two distinct gas positions.
proc service(fields: openArray[uint64]): ServiceStatisticsEntry =
  doAssert fields.len == 12
  result.service = ServiceIndex(fields[0])
  for measure in ServiceMeasure:
    let position = if ord(measure) < 3: ord(measure)+1 else: ord(measure)+2 # Skip the refinement-gas field.
    result.statistics.counters[measure] = ActivityNatural(fields[position])
  result.statistics.refinementGas = ActivityGas(fields[4])
  result.statistics.accumulationGas = ActivityGas(fields[11])

## Preserve all decimal source arrays and exact shape, including deliberately incorrect populations.
proc source(parts: seq[string]): ActivityState =
  for epoch in StatisticsEpoch:
    let fields = numbers(parts[6+ord(epoch)])
    doAssert fields.len mod 6 == 0
    result.validators[epoch] = newSeq[ValidatorActivity](fields.len div 6)
    for i in 0..<result.validators[epoch].len:
      for measure in ValidatorMeasure: result.validators[epoch][i][measure] = ValidatorCounter(
          fields[i*6+ord(measure)]) # Fixed E4 source values.
  let cores = numbers(parts[8])
  doAssert cores.len mod 8 == 0
  for i in 0..<cores.len div 8: result.cores.add(core(cores.toOpenArray(i*8,
      i*8+7))) # Fixed core positions retain source order.
  let services = numbers(parts[9])
  doAssert services.len mod 12 == 0
  for i in 0..<services.len div 12: result.services.add(service(services.toOpenArray(i*12,
      i*12+11))) # No source sorting or deduplication.

## Append one logical number rather than using native encoding to manufacture decode expectations.
proc add(fields: var seq[string], value: uint64) = fields.add($value)

## Read copied fields through the owner interface after caller input has been destroyed.
proc observation(owner: ActivitySnapshot, consumed: int): string =
  let info = activityInfo(owner).value
  result = $consumed
  for epoch in StatisticsEpoch:
    var fields: seq[string]
    for i in 0..<info.validators[epoch]:
      let record = validatorActivityAt(owner, epoch, StatisticsValidatorIndex(i)).value
      for measure in ValidatorMeasure: fields.add(uint32(record[measure])) # Observe all six fixed counter values.
    result.add(" " & $info.validators[epoch] & ":" & (if fields.len == 0: "-" else: fields.join(
        ","))) # Preserve empty array observations.
  var fields: seq[string]
  for i in 0..<info.cores:
    let record = coreActivityAt(owner, StatisticsCoreIndex(i)).value
    for measure in CoreMeasure: fields.add(uint64(record.counters[
        measure])) # Natural counters keep their logical field order.
    fields.add(uint64(record.gas))
  result.add(" " & $info.cores & ":" & (if fields.len == 0: "-" else: fields.join(
      ","))) # Fixed core count remains observable.
  fields = @[]
  for i in 0..<info.services:
    let record = serviceActivityAt(owner, StatisticsServiceIndex(i)).value
    fields.add(uint32(record.service))
    for measure in ServiceMeasure:
      fields.add(uint64(record.statistics.counters[measure]))
      if measure == ServiceMeasure.RefinementCount: fields.add(uint64(
          record.statistics.refinementGas)) # Gas sits after refinement count.
    fields.add(uint64(record.statistics.accumulationGas))
  result.add(" " & $info.services & ":" & (if fields.len == 0: "-" else: fields.join(
      ","))) # Empty service dictionary differs from failure.

## Execute one trusted request, returning either full observations or only a failure reason.
proc request(parts: seq[string]) =
  let config = ActivityConfig(cores: CoreCount(parseBiggestUInt(parts[1])), current: ValidatorCount(
      parseBiggestUInt(parts[2])),
    previous: ValidatorCount(parseBiggestUInt(parts[3])), maxServices: ElementLimit(
        parseBiggestUInt(parts[4])), maxBytes: ByteLimit(parseBiggestUInt(parts[5])))
  case parts[0]
  of "V", "R":
    var state = source(parts) # Trusted field transport is independent of the production decoder.
    let encoded = activityStateEntry(state, config)
    if encoded.error != ActivityError.None:
      echo ($encoded.error).toLowerAscii() # Failure cannot expose default bytes.
    else:
      for epoch in StatisticsEpoch:
        for i in 0..<state.validators[epoch].len: state.validators[epoch][i] = default(
            ValidatorActivity) # Destroy mutable sources before output observation.
      for i in 0..<state.cores.len: state.cores[i] = default(CoreActivity)
      for i in 0..<state.services.len: state.services[i] = default(ServiceStatisticsEntry)
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(
              1))) # Partial C(13) root only, not a whole JAM state root.
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    var bytes = unhex(parts[6]) # Hostile bytes need not represent any valid source shape.
    let decoded = decodeActivityState(bytes, config)
    if decoded.error != ActivityError.None:
      echo ($decoded.error).toLowerAscii() # No owner or consumed extent after late failures.
    else:
      for i in 0..<bytes.len: bytes[i] = 0 # Observations must survive caller wire destruction.
      echo observation(decoded.value.snapshot, decoded.value.consumed)
  else: doAssert false # Unknown trusted operations cannot select another protocol schema.

# Each request independently owns and releases its temporary arrays and retained snapshot.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty transport lines contain no request.
