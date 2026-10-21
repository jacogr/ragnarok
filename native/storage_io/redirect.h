/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Include real SDK prototypes first so SDK assembler aliases cannot defeat test call redirection. */
#ifndef RAGNAROK_STORAGE_IO_REDIRECT_H
#define RAGNAROK_STORAGE_IO_REDIRECT_H
#include <unistd.h>
#include "observer.h"
#ifdef RAGNAROK_STORAGE_IO_READ
#define read storage_io_read
#endif
#ifdef RAGNAROK_STORAGE_IO_WRITE
#define write storage_io_write
#endif
#ifdef RAGNAROK_STORAGE_IO_FSYNC
#define fsync storage_io_fsync
#endif
#endif
