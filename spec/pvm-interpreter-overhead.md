# Interpreter continuation overhead

Remove a repeated cache reset when the common checked interpreter prepares a successful host resume.
Original source instructions, gas accounting and invocation-local state remain authoritative.

## Host-resume cache reset

A successful `resumeFlatHostMemory` prepares the next dispatch and no longer clears the 256-entry
`dynamicOffsets` array itself. The following `runFlat` entry still clears all 2,048 bytes before
dispatch. Frame initialization, refused/fallback resumes, dirty-page handling and every other
reset remain unchanged. The successful resume path does not execute a guest instruction between
preparing the frame and that next entry.

The isolated candidate was reviewed at runtime SHA-256
`a8a6b4f395876fd400b8772e78401f25237f315cf70e137a905c4edcd7e33dbf`.
Existing `pvm_stream_host_resume` and `pvm_stream_resource_transfer_boundary` passed checked
ARC/Clang ThinLTO ARM profiles. Source-bound generated C and linked inspection retained the
`runFlat` clear and confirmed that successful resume no longer clears those bytes. This is
correctness and lowering evidence; it does not establish a performance benefit.

The existing entry clear is retained. This change does not alter indirect-cache initialization,
native emitters or continuation limits. Combined behavioral and exact-head performance qualification
will precede any claim of a measured benefit.
