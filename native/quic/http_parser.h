/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */
#ifndef RAGNAROK_HTTP_PARSER_H
#define RAGNAROK_HTTP_PARSER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Exclusive request-head owner. No sockets, tasks, application policy or body reads. */
typedef struct rq_http_head rq_http_head;
rq_http_head *rq_http_head_new(void);
void rq_http_head_free(rq_http_head *head);
size_t rq_http_max_head_bytes(void);
/* Input is the accumulated unread buffer; prior bytes must remain unchanged.
 * Returns 0 while incomplete, -1 on invalid input, -2 on the library head limit,
 * or the positive head extent. Body/upgrade suffix bytes are never consumed. */
int rq_http_head_scan(rq_http_head *head, const char *input, size_t length);
/* Views are valid until free and exposed only after a successful head scan.
 * part: 0 method, 1 target, 2 version, 3 named header (case insensitive). */
const char *rq_http_head_value(const rq_http_head *head, int part,
                               const char *name, size_t name_length, size_t *length);
size_t rq_http_head_count(const rq_http_head *head, const char *name, size_t length);
/* No Content-Length yields zero; callers distinguish absence through count. */
uint64_t rq_http_head_content_length(const rq_http_head *head);

#ifdef __cplusplus
}
#endif
#endif
