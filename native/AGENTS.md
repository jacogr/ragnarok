# Foreign interface instructions

Keep maintained C/Rust interfaces narrow: cryptographic primitives, LSQUIC/TLS and OS services.
JAM protocol behavior stays in Nim. Preserve explicit foreign/callback lifetimes, non-copyable
composite owners and stable worker addresses through join; release resources on every exit.

C uses four-space indentation. Rust uses pinned `rustfmt` defaults (four spaces, 100 columns),
through `make format` / `make format-check`. Keep upstream sources pristine and pinned.
