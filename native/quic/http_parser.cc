// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Narrow Balsa request-head adapter. Balsa owns incremental parsing and copied
// header storage; Nim owns I/O, routes, admission and body authorization. A scan
// processes only the new suffix of the unchanged unread buffer. It stops at
// HeaderDone before any body or WebSocket bytes, with sticky failure outcomes.
#include "http_parser.h"
#include <algorithm>
#include <limits>
#include <new>
#include "quiche/balsa/balsa_frame.h"
#include "quiche/balsa/noop_balsa_visitor.h"

namespace {
// The framer borrows this visitor, which lives inside the same exclusive owner.
struct HeadVisitor : quiche::NoOpBalsaVisitor {
    bool complete = false;
    void HeaderDone() override { complete = true; }
};
}

// Declaration order keeps the visitor and owned headers alive through framer destruction.
struct rq_http_head {
    quiche::BalsaHeaders headers;
    HeadVisitor visitor;
    quiche::BalsaFrame frame;
    size_t consumed = 0;
    int result = 0;

    rq_http_head() {
        frame.set_balsa_headers(&headers);
        frame.set_balsa_visitor(&visitor);
        // Single-request endpoints must reject ambiguous body extents before authorization.
        auto policy = frame.http_validation_policy();
        policy.disallow_multiple_content_length = true;
        policy.disallow_transfer_encoding_with_content_length = true;
        frame.set_http_validation_policy(policy);
    }
    // The framer borrows these exact member addresses throughout this allocation's lifetime.
    rq_http_head(const rq_http_head &) = delete;
    rq_http_head &operator=(const rq_http_head &) = delete;
};

extern "C" rq_http_head *rq_http_head_new(void) {
    // Foreign exceptions cannot cross the C boundary or leave a partial owner published.
    try { return new rq_http_head(); }
    catch (...) { return nullptr; }
}

extern "C" void rq_http_head_free(rq_http_head *head) { delete head; }

extern "C" size_t rq_http_max_head_bytes(void) {
    // Query the pinned library default rather than duplicating a local header-size policy.
    return quiche::BalsaFrame().max_header_length();
}

extern "C" int rq_http_head_scan(rq_http_head *head, const char *input, size_t length) {
    if (!head) return -1;
    if (head->result != 0) return head->result;
    if (length < head->consumed || (!input && length)) return head->result = -1;
    try {
        // Balsa excludes skipped leading CR/LF from its internal header accounting.
        // The Reader retains those bytes, so apply the same library limit to the
        // complete wire head. Cap the feed rather than rejecting a large unread
        // buffer: a bounded head may arrive with a much larger coalesced body.
        const size_t limit = head->frame.max_header_length();
        if (length > head->consumed)
            head->consumed += head->frame.ProcessInput(input + head->consumed,
                std::min(length - head->consumed, limit - head->consumed));
        if (head->frame.Error())
            return head->result = head->frame.ErrorCode() == quiche::BalsaFrameEnums::HEADERS_TOO_LONG
                                      ? -2 : -1;
        if (head->visitor.complete) {
            // The default library head limit also bounds the C ABI extent conversion.
            if (head->consumed > static_cast<size_t>(std::numeric_limits<int>::max()))
                return head->result = -1;
            return head->result = static_cast<int>(head->consumed);
        }
        // Completion at exactly the limit is valid; an incomplete head at that
        // extent cannot fit. Refuse before the caller fills its Reader again.
        if (length >= limit) return head->result = -2;
        return 0;
    } catch (...) { return head->result = -1; }
}

extern "C" const char *rq_http_head_value(const rq_http_head *head, int part,
                                            const char *name, size_t name_length, size_t *length) {
    if (!length) return nullptr;
    *length = 0;
    if (!head || head->result <= 0 || (!name && name_length)) return nullptr;
    absl::string_view value;
    switch (part) {
        case 0: value = head->headers.request_method(); break;
        case 1: value = head->headers.request_uri(); break;
        case 2: value = head->headers.request_version(); break;
        case 3: value = head->headers.GetHeader(absl::string_view(name, name_length)); break;
        default: return nullptr;
    }
    *length = value.size();
    return value.data();
}

extern "C" size_t rq_http_head_count(const rq_http_head *head, const char *name, size_t length) {
    if (!head || head->result <= 0 || !name || !length) return 0;
    size_t count = 0;
    for (const auto &line : head->headers.lines(absl::string_view(name, length))) {
        (void)line; // Count actual field lines; do not collapse ambiguous application selectors.
        ++count;
    }
    return count;
}

extern "C" uint64_t rq_http_head_content_length(const rq_http_head *head) {
    if (!head || head->result <= 0 || !head->headers.content_length_valid()) return 0;
    return head->headers.content_length();
}
