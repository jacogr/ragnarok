## Isolated actual/default service-value reads require success; native refusals use a separate test-only bridge.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_service_values
# Native fault injection is linked only in this isolated test adapter, never production binaries.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
fail(0)
let useDefault = paramStr(2) == "default"
let policy = ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(3))
let noKey = ServiceEntryLimits(keyBytes: ByteLimit(0), valueBytes: ByteLimit(3))
let noValue = ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(0))
let key = serviceStorageKey(ServiceIndex(1), [1'u8], ByteLimit(1)).value
let owner = captureServiceValue(ServiceIndex(1), key, [17'u8, 18, 19], ByteLimit(3)).value
let data = owner.data
assert data != nil
var output = @[77'u8, 77, 77]
var short = @[77'u8, 77]
case paramStr(1)
of "storage-key-policy":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateKey]) else: serviceStorageKey(
      ServiceIndex(1), [1'u8], ByteLimit(0))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "storage-key-backend":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  fail(1)
  let parsed = if useDefault: default(ServiceValueResult[StateKey]) else: serviceStorageKey(
      ServiceIndex(1), [1'u8], ByteLimit(1))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.BackendFailure)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "preimage-key-policy":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateKey]) else: servicePreimageKey(
      ServiceIndex(1), default(ServicePreimageHash), ByteLimit(31))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "preimage-key-backend":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  fail(1)
  let parsed = if useDefault: default(ServiceValueResult[StateKey]) else: servicePreimageKey(
      ServiceIndex(1), default(ServicePreimageHash), ByteLimit(32))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.BackendFailure)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "storage-entry-value":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: serviceStorageEntry(
      ServiceIndex(1), [1'u8], [17'u8], noValue)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "storage-entry-key":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: serviceStorageEntry(
      ServiceIndex(1), [1'u8], [17'u8], noKey)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "storage-entry-backend":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  fail(1)
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: serviceStorageEntry(
      ServiceIndex(1), [1'u8], [17'u8], policy)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.BackendFailure)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "preimage-entry-value":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: servicePreimageEntry(
      ServiceIndex(1), default(ServicePreimageHash), [17'u8], noValue)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "preimage-entry-key":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: servicePreimageEntry(
      ServiceIndex(1), default(ServicePreimageHash), [17'u8], noKey)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "preimage-entry-backend":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  fail(1)
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: servicePreimageEntry(
      ServiceIndex(1), default(ServicePreimageHash), [17'u8], policy)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.BackendFailure)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "capture-policy":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[
      ServiceValueSnapshot]) else: captureServiceValue(ServiceIndex(1), key, [17'u8], ByteLimit(0))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "capture-key":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[
      ServiceValueSnapshot]) else: captureServiceValue(ServiceIndex(2), key, [17'u8], ByteLimit(1))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.InvalidServiceKey)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "info-owner":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[ServiceValueInfo]) else: serviceValueInfo(
      default(ServiceValueSnapshot))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.InvalidOwner)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.length
of "copy-owner":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[int]) else: copyServiceValue(default(
      ServiceValueSnapshot), output)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.InvalidOwner)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "copy-short":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[int]) else: copyServiceValue(owner, short)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.OutputTooSmall)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "copy-alias":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[int]) else: copyServiceValue(owner, data.bytes)
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.AliasedBuffers)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
of "entry-owner":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: serviceValueEntry(
      default(ServiceValueSnapshot), ByteLimit(3))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.InvalidOwner)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "entry-policy":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[StateEntry]) else: serviceValueEntry(owner,
      ByteLimit(2))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LimitExceeded)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value.value.len
of "scratch-extent":
  # Defaults and actual failures cannot authorize keys, bytes, retained owners or completed progress.
  let parsed = if useDefault: default(ServiceValueResult[int]) else: storageExtent(high(int))
  assert parsed.error == (if useDefault: ServiceValueError.Uninitialized else: ServiceValueError.LengthOverflow)
  assert output == @[77'u8, 77, 77] and short == @[77'u8, 77] and data.bytes == @[17'u8, 18, 19]
  discard parsed.value
else:
  # Unknown fixture modes are setup failures rather than contract-rejection evidence.
  quit 2
