# Local JAM fuzzer transport

The pinned conformance protocol requires a target-owned Unix SOCK_STREAM listener,
sequential request/response frames, continued listening after disconnect and a
fresh session for each connection. This layer implements those transport duties
under explicit byte and absolute request/response deadline limits. It does not
classify STF outcomes or accept any fuzz seed as production chain trust.

Completion witnesses exercise real local sockets, fragmented input, framed
handshake output, backend request/reply handoff, peer disconnect/reconnection,
malformed input, deadlines and descriptor/path cleanup. Socket ownership is
move-only and cleanup may remove only the inode actually bound by that lifetime.
A host must execute requests outside transport ticks, answer only genuine consensus
import failures with Error, and retire backend session state on disconnect.

The listener admits one active session and performs at most one 4096-byte receive
and one 4096-byte send per tick. Frame input and output have independent bounded
owners; partial writes retain exact offsets. Requests have absolute deadlines,
including assembly and host execution; partial progress cannot keep a request
alive indefinitely. The deadline resets only after a complete response drains.
The host observes a monotonic connection generation to reset backend state.

Startup requires an absolute bounded socket path in an existing private directory
owned by the effective user. Existing files/sockets are refused without unlinking.
Descriptors are nonblocking and close-on-exec; SIGPIPE cannot terminate the host.
