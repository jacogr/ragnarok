## Trial-only subprocess failures prove checked release builds still execute runtime guards.
import std/[assertions, cmdline, syncio]
# Runtime argument values prevent folding either invalid operation into a compile-time diagnostic.
case paramStr(1)
of "assertion":
  # An always-false assertion must terminate even in optimized release mode.
  assert false, "trial assertion sentinel"
of "bounds":
  # One supplied argument indexes past this one-element sequence.
  let bytes = @[byte(7)]
  echo bytes[paramCount()]
of "overflow":
  # One supplied argument leaves the addend one above the largest signed integer.
  let value = high(int) - paramCount()
  echo value + 2
else:
  # Unknown modes are fixture mistakes and must never count as a tested guard.
  quit 2
