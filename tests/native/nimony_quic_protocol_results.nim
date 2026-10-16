## Every unsuccessful/default/pending parser result must reject payload selection at its contract.
import std/[assertions, cmdline, syncio]
import ../../src/quic/protocol

# One process observes one rejected read so an earlier failure cannot hide a later accessor.
proc main() {.raises.} =
  let args = commandLineParams()
  assert args.len == 2
  if args[0] == "length":
    # Length parsing has defaults and actual malformed headers; pending belongs only to frame results.
    var checked = default(LengthResult)
    if args[1] == "error": checked = checkedLength([], 1024) # No complete header exists.
    echo checked.value
  else:
    # The same success-only metadata guard protects defaults, actual failures and incomplete directions.
    var checked = default(FrameResult)
    if args[1] == "error": checked = inspectFrame([0'u8], true, 32, true) # Wrong CE selector.
    elif args[1] == "pending": checked = inspectFrame([], true, 32, false) # A live incomplete stream.
    if args[0] == "size": echo checked.size # No failed/default/pending payload size exists.
    else: echo checked.extent # No failed/default/pending frame extent exists.

# Trusted command-line failure is distinct from the expected contract trap.
try:
  main()
except:
  quit(2)
