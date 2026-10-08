# XYZ Society — Full Build Plan (follows the Project Specification v1, 8 Oct 2026)

Private, mobile-friendly society website on Lovable Cloud. Nothing is visible without an approved account. Every rule below is enforced on the backend, not only by hiding buttons. Status: Stage 1 database (accounts, houses, memberships, roles, permissions, audit, notifications) is already in place.

## 1. Login and accounts
- Sign in with mobile number + password. 9876543210, 09876543210 and +91 9876543210 are the same account. No OTP, SMS, email or WhatsApp.
- Passwords are handled by Lovable Cloud's sign-in service (hashed, never visible). The mobile number is turned into a private sign-in key that is never shown, never emailed, never listed anywhere.
- Account states: Pending society approval, Pending household approval, Active, Rejected, Suspended. Suspension cuts access immediately and keeps history.
- Admin-created accounts get a temporary password and must change it on first login.
- Forgotten password: admin verifies the person offline, issues a temporary password (audited). Admin can never see a password.
- First Society admin: one-time setup screen protected by a setup code you choose; creates the admin and their real house, then locks itself.

## 2. Joining paths
- Existing approved account: log in.
- Existing house: register, pick house number, wait for that house admin.
- Family invitation link: revocable, expires in 7 days (configurable), shows only the house number. Registrant waits for house-admin approval. Cannot create a second account for an existing mobile or move someone silently.
- New house: register with house number, row/block, owner/tenant status. Society admin (or a manager with membership-review permission) checks duplicates and approves; applicant becomes house admin.
- Admin provisioning: admin creates a house and its account directly.
- Pending users only see login, registration, invitation and "my request status" screens.

## 3. Roles and permissions
- Exactly four roles: Society admin, Society manager, House admin, House member. Money collector is a designation.
- Manager permission editor grouped as: Membership, Houses, Charges, Projects, Official updates, Complaints (priority / status / self-assign / assign), Suggestions, Financial recording, Reports, Moderation. Conservative starting template = viewing, discussions, complaint self-assignment.
- Reserved for Society admin only: final financial approval, expense approval, corrections/reversals, roles, collectors, bank accounts. No manager grant can override this. Managers cannot grant themselves anything. All changes audited.

## 4. Houses and residents
- House fields: number (unique within row/block), row/block, address, occupancy, owner/tenant classification, owner details, current tenant details, start dates, notes, primary house admin, members. States: Pending, Active, Archived. No ID documents.
- Searchable directory (number, block, name, occupancy, status); phone visibility controlled by admin.
- House page: members, admin, charges, total assessed, approved paid, pending claims, outstanding dues, transaction history.
- Tenant / house-admin changes keep full history and effective dates; dues stay with the house. Cannot archive a house with outstanding dues or open transactions.
- Overview counts: total houses, active houses, active approved members, paid/unpaid houses, pending requests (not presented as total residents).

## 5. Charges, dues and maintenance
- Charge form: title, purpose, amount per house, assessment date, optional due date, category (Setup, Project, Maintenance, Other), optional project, description.
- Choose all active houses, individual houses, or by row/block; preview count and total before publishing. House set is frozen; adding a house later is explicit and audited. Double clicks cannot issue twice.
- Partial payments; explicit allocation of one collection across several charges (must add up exactly). No allocation above dues, no advance wallet.
- Dues = assessments − approved allocations − waivers + reversed allocations. Pending/disputed/rejected claims never reduce dues (₹1,000 − pending ₹400 = ₹1,000 due; after approval ₹600 due).
- Waivers need a reason, reduce dues, never add cash.
- Monthly maintenance off by default. Admin sets amount, houses, first billing month (no backdating), due-day rule, then enables. Daily backend job generates exactly one assessment per house per period. Pause/amount changes affect future periods only.

## 6. Money holders
- Person-held collector accounts (only explicitly authorized members) and society bank accounts (masked details, admin oversight).
- Each shows posted balance, reserved outgoing, available balance and full movement history.
- Record types: household collection, opening/legacy funds, internal transfer, expense payment, reimbursement, refund, reversal, adjustment.
- Opening funds (e.g. ₹10,00,000) need source description, date, receiving account, receiver confirmation, admin approval; shown separately and never change dues.
- Reimbursing a collector personally is an expense settlement, not a transfer into their society account.

## 7. Two-sided confirmation and approval
- One shared record per transaction: stable reference, type, amount, date, purpose, sender, receiver, accounts, house/expense/project link, evidence, revision, separate sender / receiver / admin fields.
- Who confirms each side follows the spec table (household payer, named collector, admin for bank side, admin-verified external recipient for vendors, receiver + evidence for opening funds).
- Responses: Confirmed, Not sent/received yet, Report a mismatch (reason required, marks Disputed, alerts admin).
- Displayed states: Awaiting sender, Awaiting receiver, Awaiting confirmations, Awaiting admin approval, Posted, Disputed, Rejected, Cancelled, Reversed.
- Admin approves only after required confirmations; posting is atomic and happens exactly once. Material edits bump the revision and require fresh confirmations; confirmations on different revisions can't complete a record.
- Admin can request revised evidence, cancel a pending record, or ask for reconfirmation; cannot override a resident's mismatch.
- Similar records (same house, amount, date, counterpart) flagged for duplicate review.
- Pending confirmations page, bell badge, dismissible login reminder (dismissing changes nothing). Confirmation screen shows amount, date, purpose, counterpart, account, link, evidence, previous responses and exactly what confirming does.

## 8. Accounting integrity
- Permanent ledger entries in whole paise; balances computed from the ledger only.
- Society cash = sum of money-holder balances = opening funds + collections − settled expenses − refunds ± corrections. Transfers net zero.
- Source balance checked at posting; pending outgoing records reserve funds; pending incoming money can't fund spending; simultaneous spends can't overdraw.
- No hard delete or silent edit of posted records; corrections via linked admin-approved reversal/adjustment with reason. Refund reopens dues; waiver reduces dues without cash.
- Worked example (Sobhan / Salman / bank / Yai) must reconcile exactly: ₹90,000 → ₹75,000 → ₹75,000 → ₹61,000, settled expenses ₹29,000.

## 9. Expenses and purchases
- Any member submits Planned or Already paid personally: title, description, amount, category, date, project/complaint link, supplier, item/service, quantity and unit, photos/receipts.
- Only Society admin approves/rejects. Planned approval authorizes spending (not paid). Actual payment recorded separately with confirmations and final approval.
- Personally paid: admin approves reimbursement and picks the paying account; payer confirms sending, resident confirms receiving, admin posts. Partial settlements allowed; never above the approved amount; one reservation per outstanding portion; rejected/cancelled settlements release it.
- Report states: requested, approved unpaid, partially paid, settled, rejected.

## 10. Projects, official updates and discussions
- Projects: title, description, category, priority, state (Planned, In progress, On hold, Completed), target date, responsible manager, budget, linked expenses/complaints/suggestions, photos, funding and spending.
- Project page: official summary and dated update timeline on top, resident discussion below.
- Official updates (project or general announcements) only by admin or managers with permission; edit and archive history kept; no limit on count.
- Comments with unlimited nested replies, mobile-friendly indentation, pagination, edit/delete own (placeholder kept when replies exist), moderation with reason and audit.
- Like/dislike on projects, updates and comments: one reaction per person, switch or remove.

## 11. Complaints and suggestions
- Separate pages. Title, description, category, location, photos, discussion, project link.
- States Open, In progress, Closed with history and closing explanation; residents request reopening; admin/authorized manager reopens with reason.
- Priority Low/Normal/High/Urgent set only by admin or permitted managers.
- Optional assignment: admin assigns; permitted manager can "Take responsibility" (two simultaneous claims cannot both win); reassign/release with reason; anyone can help and comment.
- Suggestions are distinct records and can be linked to projects.

## 12. Notifications and audit
- In-app notifications for membership decisions, charges, confirmations, expense decisions, reimbursements, disputes, approvals, official updates, replies, assignment, priority and status changes. Read/dismiss never touches the source record.
- Audit trail of actor, time, changed values, reason, confirmation and approval history for all financial and administrative actions.

## 13. Pages
Resident: Society overview, My house, Houses and residents, Contributions and dues, Collections and transactions, Funds and accounts, Expenses and purchases, Projects, Official updates, Complaints, Suggestions, Pending confirmations, Notifications, Activity and audit, My profile.
Management (shown by permission): Membership requests, House administration, Members, Manager permissions, Collectors and bank accounts, Charges and maintenance, Financial approvals, Expense approvals, Project and update editor, Complaint and suggestion management, Society settings (name, logo, description, contact, phone visibility, invite expiry), Audit review.
Reports with filters and CSV export: house dues, charge progress, money-holder balances, collections, expenses, unpaid expenses, transfers, audit history.
Design: clean light interface, restrained blue, clear labels, INR formatting (₹10,00,000), India Standard Time dates, mobile navigation, loading/empty/error/pending/disputed/rejected states everywhere.

## 14. Demo data
Optional, clearly labelled sample data kept separate from real records; off by default and removable.

## 15. Build order
1. Accounts, joining, roles, houses (database done; screens next)
2. Money holders, transactions, confirmations, ledger, approvals
3. Charges, dues, waivers, maintenance schedule
4. Expenses and reimbursements, file uploads
5. Projects, updates, comments, reactions, complaints, suggestions
6. Overview, reports, CSV, notifications, audit pages, settings
7. Run all 15 acceptance scenarios and report results honestly, including anything unfinished

## Technical details
- Security-definer database functions perform every write with permission checks; row-level security limits reads to active members; roles in a separate table.
- Financial posting uses row locks and idempotency keys; ledger rows cannot be updated or deleted.
- Private file storage; files readable only by active members.
- Maintenance via a daily database schedule with a unique (house, schedule, period) constraint.
- Admin account creation and password resets run in protected server functions.
