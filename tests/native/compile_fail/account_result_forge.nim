## Application code cannot forge success or mutate a read-only result accessor.
import ../../../src/codec/state_accounts
discard ServiceMetadataResult[ServiceMetadataRead](status: ServiceMetadataError.None,
    completed: default(ServiceMetadataRead))
