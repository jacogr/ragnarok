/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Borrowed strings remain stable during the public libFuzzer driver call; no native ownership escapes. */
#ifndef RAGNAROK_FUZZ_DRIVER_H
#define RAGNAROK_FUZZ_DRIVER_H
int ragnarok_fuzz_run(const char *corpus, const char *runs, const char *artifacts);
#endif
