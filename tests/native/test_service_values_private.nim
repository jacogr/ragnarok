## Privileged native misuse test: safe public APIs cannot expose a backing alias, but atomic copy still guards it.
include ../../src/state_service_values

## Exact and shifted retained-storage destinations must reject before modifying any captured byte.
proc main() =
  let key = serviceStorageKey(ServiceIndex(1), @[1'u8], ByteLimit(1)).value
  let owner = captureServiceValue(ServiceIndex(1), key, @[17'u8, 18, 19], ByteLimit(3)).value
  let exact = copyServiceValue(owner, owner.data.bytes)
  doAssert exact.error == ServiceValueError.AliasedBuffers and owner.data.bytes == @[17'u8, 18, 19]
  let shifted = copyServiceValue(owner, owner.data.bytes.toOpenArray(1, 2))
  doAssert shifted.error == ServiceValueError.OutputTooSmall and owner.data.bytes == @[17'u8, 18, 19]
  echo "PASS service values: private native alias rejection and unchanged backing bytes"

main()
