# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Cached request keys cannot bypass whole-output frozen reconstruction admission.
# @@Verification={"group":"nominal","expected":"CurrentRefreshPlan","early":["executeCurrentRefresh(","[1] expected: CurrentRefreshPlan but got: CurrentRequestKeys"]}
import ../../../src/state/current/[refresh as current_refresh, request_keys as current_request_keys]
discard executeCurrentRefresh(default(CurrentRequestKeys))
