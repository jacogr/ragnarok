# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real libFuzzer ABI plus bounded standalone artifact replay share the exact program decoder properties after ordinary Nimony initialization.
import std/[assertions, syncio, cmdline]
import ./pvm_program_target
when defined(fuzzReplay):
  # Standalone replay uses no fuzzer runtime; malformed bytes are ordinary decoder refusals, while property defects remain fatal.
  if paramCount() == 0: quit(2)
  for index in 1..paramCount():
    var file: File = nil
    if not open(file, paramStr(index), fmRead): quit(2)
    var bytes = newSeq[byte](ProgramFuzzBytes+1)
    let count = readBuffer(file, addr bytes[0], bytes.len)
    close(file)
    if count < 0 or count > ProgramFuzzBytes: quit(2)
    bytes.setLen(count)
    discard exerciseProgramBytes(bytes)
  echo "PVM program fuzz replay passed: ", paramCount()
else:
  # Exact C-compatible callback types match the public libFuzzer interface; runtime/ARC startup already occurred through this generated main.
  proc initialize(argc: ptr cint, argv: ptr ptr cstring): cint {.cdecl,
      exportc: "LLVMFuzzerInitialize", raises: [].} =
    0
  proc testOneInput(data: ptr UncheckedArray[byte], length: csize_t): cint {.cdecl,
      exportc: "LLVMFuzzerTestOneInput", raises: [].} =
    if length > csize_t(ProgramFuzzBytes): return 0
    when defined(fuzzAssertionControl):
      assert length == 0 # Controlled valid seed failure must terminate and save an artifact rather than being caught as ordinary input rejection.
    var bytes = newSeq[byte](int(length))
    for index in 0..<bytes.len: bytes[index] = data[
        index] # libFuzzer owns this bounded readable buffer only for the callback duration.
    discard exerciseProgramBytes(bytes)
    0
  proc run(corpus, runs, artifacts: cstring): cint {.cdecl, importc: "ragnarok_fuzz_run",
      header: "fuzz_driver.h", raises: [].}
  if paramCount() != 3: quit(2)
  var corpus = paramStr(1)
  var runs = paramStr(2)
  var artifacts = paramStr(3)
  quit int(run(corpus.toCString(), runs.toCString(), artifacts.toCString()))
