## Rejected misuse: bounded result state is private and its public reason is read-only.
import ../../../src/codec/bounded
discard BlobResult(status: ContainerError.None, byteOffset: 0, byteLength: 0, byteConsumed: 0)
