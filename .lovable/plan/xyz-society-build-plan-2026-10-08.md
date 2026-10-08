# XYZ Society — Build Plan

A private, mobile-friendly society management website backed by Lovable Cloud (database, login, file storage, scheduled jobs). The full specification is the acceptance contract; it is delivered in stages so each stage is working and verified before the next.

## Login decision (needs your OK)
- Residents sign in with **mobile number + password**, no OTP/SMS.
- Lovable Cloud's built-in phone login always sends an SMS code, so instead each mobile number is normalised (e.g. +919876543210) and mapped to a hidden internal sign-in identifier that is never shown, never emailed, and never used as contact info. Passwords are hashed by Lovable Cloud; nobody (including admins) can see them.
- Admin-issued temporary passwords force a password change on first login; every reset is audited.
- First Society admin: created once via a one-time secure setup screen protected by a setup secret you store in project settings; it is disabled afterwards and must be linked to a real house.

## Stages
1. **Foundation** — design system (light, restrained blue, INR, Asia/Kolkata), login, registration, family invites, new-house requests, account states (Pending society / Pending household / Active / Rejected / Suspended), houses, memberships with history, four roles + manager permission editor, approval-status screens, all data access locked to active members on the backend.
2. **Money core** — fund accounts (collectors, bank accounts), shared transactions with sender/receiver confirmation, disputes, admin final approval, immutable ledger in integer paise, atomic exactly-once posting, overspend protection, reversals/adjustments, pending-confirmations queue.
3. **Dues** — charges (all/individual/by block, preview, fixed house set), partial payments, multi-charge allocation, waivers, monthly maintenance with backend schedule (once per house per period).
4. **Expenses** — planned and personally-paid expenses, admin approval, reimbursements with partial settlement and reservation, evidence uploads.
5. **Community** — projects, official updates timeline, nested comments, reactions, complaints (priority, assignment, take responsibility with race protection, reopen), suggestions, moderation.
6. **Transparency** — overview dashboard, reports with CSV export, notifications, audit log, all navigation pages listed in the spec.
7. **Verification** — run all 15 acceptance scenarios (e.g. ₹400 claim vs ₹1,000 due; Sobhan/Salman/Yai fund scenario; double-click posting) and report results, including anything unfinished.

## Technical details
- TanStack Start server functions with auth middleware for all reads/writes; RLS keyed on an `is_active_member()` check; roles in a separate `user_roles` table with `has_role()`/`has_permission()` security-definer functions.
- Financial posting via Postgres functions with row locks and idempotency keys; balances derived from ledger entries only.
- Private storage bucket for evidence; signed URLs issued only to active members.
- Maintenance generation via pg_cron calling a protected server route, unique constraint on (house, charge-series, period).
- Demo data kept in a separate, clearly labelled seed that is off by default.
