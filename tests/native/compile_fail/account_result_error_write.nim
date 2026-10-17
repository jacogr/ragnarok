## Application code cannot forge success or mutate a read-only result accessor.
import ../../../src/codec/state_accounts
var parsed = default(ServiceMetadataResult[ServiceMetadataRead])
parsed.error = ServiceMetadataError.None
