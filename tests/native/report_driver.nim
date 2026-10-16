## Full report adapter: the crypto check subcommand and standalone codec batch share exact codec coverage.
import std/[cmdline, syncio]
import ./report_check
# Explicit credential verification remains a separate integration workload.
if paramCount() > 0 and paramStr(1) == "check":
  try:
    reportFixtureCheck()
  except:
    # A malformed trusted fixture or I/O failure cannot count as a credential verdict.
    quit(2)
  quit(0)
# Every ordinary request uses the same complete codec/owner adapter as the Nimony trial.
include ./report_codec_driver
