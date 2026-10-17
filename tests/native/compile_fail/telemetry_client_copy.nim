## A telemetry descriptor has one owner even when wrapped in fixed queue/configuration storage.
import ../../../src/telemetry/client
var original = default(Client)
var duplicate = original
original.close()
duplicate.close()
