# Your Staff Delivery — Independent operations and manual dispatch

Approved scope on 2026-11-19: improve software independence, deterministic operational decisions, security, capacity tests and disaster recovery. Automatic order allocation and automatic driver assignment are EXCLUDED.

## Core behavior
- Current GitHub app runs a JavaScript frontend and Supabase PostgreSQL functions. Order creation and the kitchen / supervisor / driver status transitions do not call generative AI providers in the inspected frontend sources.
- Owner administrative assistant uses a predefined Arabic command parser and an authorized database workflow; it is not a general AI model dependency.
- Manual dispatch continues to require a supervisor or owner role, explicit driver selection, and owner confirmation on owner assignment. Backend authorization remains authoritative.
- The regression test tests/core_independence_manual_dispatch.test.cjs detects direct known AI API URLs in current frontend files and disappearance of manual-assignment checks. This is not a comprehensive runtime dependency audit.

## Deterministic performance metrics
- operational-rules.js is an independent pure calculation module, returning reproducible counts and kitchen/delivery delay aggregates. It needs an explicit timestamp and branch-specific SLA thresholds from authorized data.
- It never assigns or suggests drivers, mutates orders, contacts an AI provider, or sends network requests.
- tests/operational_rules_deterministic.test.cjs checks reproducibility, input immutability, time thresholds, and 500 offline synthetic order fixtures.
- The KPI module is not yet wired into the production dashboard; existing live operational calculations remain authoritative. The 500-fixture calculation is NOT proof of capacity at 500 real orders or 200 concurrent users.

## Required production verification still outstanding
- Do not replace current TackHost index.html from GitHub, since hosting contains newer/different production changes. Back up current live files, create a minimal additive patch and verify on Test.
- Maintain strict per-company/branch RLS and session rules on the backend; never rely on hiding UI elements.
- Prove encrypted offsite Supabase backup AND restore, plus daily close/archive behavior and 90-day retention obligations before deleting any operating data.
- Run realistic multi-device GPS/privacy and high-load tests in staging. Do not create synthetic orders or employee accounts in production.
- Supabase Free Realtime peak-connections limit remains 200; code fixes reduce unnecessary sockets but do not increase the quota.
- Automatic driver assignment is prohibited unless the user makes a separate, explicit request.

## Automated safety
GitHub Actions Commercial release smoke runs Python smoke checks and Node test files for pull requests and main branch pushes. No external AI service is required for these tests.