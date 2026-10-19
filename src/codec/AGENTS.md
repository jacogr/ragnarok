# Codec implementation instructions

Read [the protocol interpretations](../../spec/AGENTS.md) before changing encodings, especially
statistics gas widths or the parked request namespace. Follow published vector widths with one
representation and no fallback. Retain malformed, truncated, overflow, ownership and important
negative-compilation coverage. Shared codecs and Merklization must remain reusable by node modes.
