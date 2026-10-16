## Full report adapter: the crypto check subcommand and standalone codec batch share exact codec coverage.
import std/cmdline
import ./report_check
# Explicit credential verification remains a separate integration workload.
if paramCount() > 0 and paramStr(1) == "check":
  reportFixtureCheck()
  quit(0)
# Every ordinary request uses the same complete codec/owner adapter as the Nimony trial.
include ./report_codec_driver
