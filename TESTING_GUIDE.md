# Vistar KRA — Testing Guide

This guide tells a tester how to verify the Vistar KRA app end-to-end: how to set up the test environment, what to test in what order, what counts as a pass or fail, and what's known to be unbuilt so you don't file noise tickets.

If you've never touched the app before, read [USER_MANUAL.md](USER_MANUAL.md) first — it explains what each screen is for. This document focuses on *how* to test, not *what* the app does.

---

## 1. Before you start

### 1.1 Build & device requirements

- A device or emulator (Android 8+, iOS 14+, or web Chrome). The Flutter desktop builds (Windows/macOS/Linux) are also supported.
- Flutter 3.10+ / Dart 3+. From the repo root:
  ```bash
  flutter pub get
  flutter analyze        # must report "No issues found"
  flutter test           # must end with "All tests passed!"
  flutter run            # launches on the connected device
  ```
- If `flutter analyze` or `flutter test` fail on a clean checkout, **stop and report to dev** — the build is broken before testing begins.

### 1.2 Test environments

| Env | URL | Use for |
|-----|-----|---------|
| **Live (test)** | `https://vistar-crm.onrender.com/api/v1/kra/` | All functional tests — this is the default the app points to. |
| **Mock** | (in-app only) | Smoke tests when the backend is down. Toggled by swapping the provider implementation; ask dev before doing this. |

**Render cold-start caveat**: the live backend is hosted on Render's free tier. The very first request after ~15 minutes of inactivity can take **30–60 seconds** to respond. Wait it out before filing a "loading forever" bug. Subsequent requests are fast.

### 1.3 Test credentials

Always sign in with a real test account — never use production credentials. All passwords are `Vistar@123`.

| Role | Email | Notes |
|------|-------|-------|
| HR_ADMIN | `hr.admin@vistar.test` | note the dot |
| MANAGER | `manager@vistar.test` | manages emp1–emp3 |
| EMPLOYEE | `emp1@vistar.test` | review state DRAFT — exercise full self-rate flow here |
| EMPLOYEE | `emp2@vistar.test` | review state EMPLOYEE_SUBMITTED_ALL — exercises the manager-rate inbox |
| EMPLOYEE | `emp3@vistar.test` | review state FINALIZED — read-only history |

If a credential is rotated or removed, ask dev for the current set — don't guess.

### 1.4 What to capture for every defect

When something doesn't match an expected result below, file a ticket with:

1. **Case ID** (e.g. *3.5* from this guide) so the dev can jump to the right step.
2. **Role + email** you were signed in as.
3. **Device + OS + build commit** (`git log -1 --oneline`).
4. **Steps to reproduce** — your exact taps, even the boring ones.
5. **What you saw** vs **what was expected**.
6. **Screenshot or screen recording** for any UI bug.
7. **Network indicator**: were you online? Was the offline banner showing?
8. **Severity** (see §7).

### 1.5 How to read the test tables

Each case row has four columns:

| Column | Meaning |
|--------|---------|
| **#** | A stable case ID — quote this in defect tickets. |
| **Action** | What you do. Bullet sub-steps if any. |
| **Expected** | What must happen. If anything else happens, it's a defect. |
| **✓** | Tick once verified on a given build. Print or copy this guide and use it as a sign-off sheet. |

A test is **PASS** only when *all* of the expected behaviour is observed. Partial wins ("it kind of works") are FAIL.

---

## 2. The testing order

Follow the quarter in calendar order — phases 2 and 3 repeat once per month before phase 4.

| Step | Role | What you do |
|------|------|-------------|
| 0 | — | Smoke-test login + app shell. |
| 1 | HR Admin | Build everything: locations, templates, employees, cycle, slabs, assign, open. |
| 2 | Employee | Self-rate the active month. |
| 3 | Manager | Rate the employee's submission; bulk-approve the team. |
| ↻ | Repeat 2 & 3 | Once each for May and June. |
| 4 | HR Admin | Watch the pipeline fill, close cycle, run payouts, check Reports & Audit Log. |
| X | Any | Cross-cutting checks (offline, loading, formatting, theming). |

If a phase blocks (e.g. you can't open a cycle in phase 1), don't skip ahead — file the blocker and stop. Later phases assume the earlier ones passed.

---

## 3. Phase 0 — Authentication & App Shell

Sign in as **HR Admin** (use this run to probe auth behaviour).

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 0.1 | Launch the app with no saved token. | Vistar logo loads, then the login screen appears. | ☐ |
| 0.2 | Leave Employee ID or password empty and tap Sign In. | Required-field validators flag both. The button does not fire a network request. | ☐ |
| 0.3 | Enter wrong credentials and sign in. | A red inline error banner appears just above the Sign In button. You stay on `/login`. | ☐ |
| 0.4 | Enter `hradmin@vistar.test` / `Vistar@123` and tap Sign In. | A spinner shows in the button during the request. You land on `/hr/home`. | ☐ |
| 0.5 | Toggle the device offline, then attempt sign-in. | The Sign In button disables and shows "Offline — sign-in unavailable". No crash. | ☐ |
| 0.6 | Kill and relaunch the app while a valid token exists. | You skip `/login` and go straight to `/hr/home` (or your role's home). | ☐ |
| 0.7 | Trigger any data call after the token is invalidated (have dev help, or wait for natural expiry). | A 401 auto-signs you out and returns you to `/login`. | ☐ |
| 0.8 | Open a deep-link the app has no screen for (e.g. `/hr/feeds/hr-feed` via a notification). | A friendly "This page isn't ready yet" screen with a working **Go to Home** button. | ☐ |

---

## 4. Phase 1 — HR Admin: Build the Cycle

Signed in as HR Admin → land on `/hr/home`. Work top-down.

### 4.1 HR Home dashboard (`/hr/home`)

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 1.1 | Open HR Home and let it settle. | All 8 sections (overview, active cycle, KPIs, funnel, action items, heatmap, recent activity, deadlines) load with shimmer first, then real content. | ☐ |
| 1.2 | Pull down to refresh. | All 8 sections refetch. After they settle, scrolling sections off-screen and back **does not** retrigger a load — the cards must stay populated. | ☐ |
| 1.3 | Tap a row in the location **heatmap**. | A bottom sheet opens with that location's cycle average, total review count, per-month breakdown, and a **View employees here** CTA. | ☐ |
| 1.4 | Tap **View employees here** from the heatmap sheet. | Navigates to `/hr/employees`. | ☐ |

### 4.2 Locations (`/hr/locations`)

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 1.5 | Tap **+**, fill name + address, save. | New location appears in the list. An audit entry is written (verify in 4.27). | ☐ |
| 1.6 | Tap an existing row. | A bottom sheet opens pre-filled. Edit, save — changes reflect in the list. | ☐ |
| 1.7 | Delete a location. | A **red** ConfirmActionDialog appears (Cancel / Remove). Only Remove deletes. | ☐ |

### 4.3 KRA Templates (`/hr/kra-templates`)

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 1.8 | Tap **+**. Fill Template Name, Description, Target Role. | Form accepts the fields. | ☐ |
| 1.9 | Tap **Add KRA**. Enter title, target, weightage, display order. | Item appears in the list. | ☐ |
| 1.10 | Make the items' weightages total **< 100%**. | Running total shown in the indicator; **Save is disabled**. | ☐ |
| 1.11 | Adjust so weightages total **exactly 100%**, then Save. | Save enables; the template persists. | ☐ |
| 1.12 | Tap an existing item to edit. | Same input row opens in-place; edits save. | ☐ |
| 1.13 | Delete a KRA item. | A red confirm dialog asks "Remove this KRA?" before deletion. | ☐ |
| 1.14 | Return to the template list. | Each tile shows **KRA count**. The weightage pill stays hidden until the full template detail has hydrated. | ☐ |

### 4.4 Employees (`/hr/employees`)

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 1.15 | Type in the search box. | After ~300ms, the list filters by name / employee code. | ☐ |
| 1.16 | Tap the **role chip** → select a role → then select **All roles**. | List narrows to that role, then resets to all employees. (This was the historical "filter sticks" bug — must be fully reversible.) | ☐ |
| 1.17 | Tap the **status chip** → Active / Inactive / Any status. | List narrows / widens accordingly. | ☐ |
| 1.18 | Tap **+**, submit with a missing field or a malformed email. | Inline form errors. No network request. | ☐ |
| 1.19 | Fill everything correctly and Save; immediately retry with a duplicate code or email. | First save succeeds. Duplicate is rejected by the server with a clear message. | ☐ |
| 1.20 | Tap an employee row. | Detail shows read-only profile + reporting manager. | ☐ |
| 1.21 | From detail, tap **Assign KRA**. | Navigates to `/hr/assign`. | ☐ |
| 1.22 | From detail, tap **Edit Profile**. | Pre-filled form opens. | ☐ |

### 4.5 Cycles & Bonus Slabs (`/hr/cycles`)

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 1.23 | Tap **+**. Fill name, start/end dates, self- and manager-rate deadlines. Save. | Cycle appears in the list with status. | ☐ |
| 1.24 | Open **Bonus Slabs** (`/hr/cycles/:id/slabs`). Define bands (e.g. 90%+ = ₹50,000; 80–90% = ₹30,000; <70% = ₹0). | Slabs save and persist on refresh. | ☐ |

### 4.6 Assign & open the cycle

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 1.25 | Assign a template to one employee from `/hr/assign`. | Assignment succeeds. | ☐ |
| 1.26 | Try assigning a **second active template** to the same employee. | Rejected — only one active template per employee. | ☐ |
| 1.27 | Open the cycle (activate it). | Active-cycle card flips to Open. Employees can now see it. | ☐ |
| 1.28 | Open **Reports → Audit Log** (`/hr/reports/audit-log`). Scroll through. | Every create / edit / delete / assign / open you just did appears, reverse-chronological. Action chips are colour-coded (CREATE green, UPDATE orange, DELETE red). | ☐ |

> **Known issue (not a bug)**: on the live test backend, cycle writes can return a 400 because the env uses slug IDs (e.g. `cyc_q1_fy2627`) while the write validators expect UUIDs. Flag this to backend, not as an app bug.

---

## 5. Phase 2 — Employee: Self-Rate

Sign out, sign in as **EMPLOYEE** → `/employee/home`.

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 2.1 | Open Home. | Greeting + current cycle, deadline banner, current-month card, My KRAs summary, incentive snapshot, history strip — all rendered. | ☐ |
| 2.2 | Note the deadline banner colour. | The banner is shown when the deadline is within 3 days or already overdue. (Colour ramp is orange → red.) | ☐ |
| 2.3 | Check the incentive snapshot. | Shows the projected payout from the latest score and the cycle's bonus slab. | ☐ |
| 2.4 | Tap **Self-Rate**. Switch months with the month picker. | The form switches months. Each KRA shows title, target, a 0–10 slider in 0.5 steps, and an optional comment field. | ☐ |
| 2.5 | Score every KRA for the current month. | The weightage progress bar fills as you go and turns **green only at 100%** (not before). | ☐ |
| 2.6 | Tap **Review & Submit**. Tap a row in the summary. | The review screen opens. **Tapping a row jumps back to the form** with that row visible. | ☐ |
| 2.7 | Submit. | The success screen appears with an **animated** illustration (staggered rings + elastic check pop). Title reads "Your review has been submitted". | ☐ |
| 2.8 | Try to self-rate a closed cycle or outside your window. | The locked screen shows with **Go to History** as the primary CTA. | ☐ |
| 2.9 | Open History → tap a cycle → tap a review. | Detail shows: self-vs-manager comparison table, score-progression chart, manager comments. | ☐ |
| 2.10 | Open Profile. Try to edit each field. | Only **phone** is editable (others read-only / HR-owned). Photo edit is marked "coming soon". | ☐ |
| 2.11 | Open the reporting tree. | Shows you + your direct manager. (Multi-level tree to CEO is not implemented yet — don't file a bug.) | ☐ |
| 2.12 | Type `/hr/employees` as a deep-link in a debug shell, or trigger any HR deep-link. | The router redirects you to your own dashboard. You never see HR screens. | ☐ |

---

## 6. Phase 3 — Manager: Rate the Team

Sign out, sign in as **MANAGER** → `/manager/team/dashboard`.

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 3.1 | Open the dashboard. | Greeting + stats (team size / pending / overdue / avg) + pending-actions sorted by deadline + team-trend card. | ☐ |
| 3.2 | Find an overdue review (if any). | The tile reads "OVERDUE" in red. Days-remaining shown otherwise. | ☐ |
| 3.3 | If a manager has no reports, view their dashboard. | A no-reports empty state. | ☐ |
| 3.4 | Open Team. Apply the state filter chips. | List filters by the chosen state. Each row shows the latest cycle state + a 3-month trend strip. | ☐ |
| 3.5 | Tap the AppBar checklist icon to enter bulk-select. | AppBar swaps to a count + actions row. Long-press to enter bulk-select is **not yet implemented** — only the AppBar icon. | ☐ |
| 3.6 | Tap a row in normal mode. | Read-only Team Member Profile; link to that person's History. | ☐ |
| 3.7 | Open Review Detail for an employee who has submitted. | Per-KRA score + comment per month, weightage + weighted total, previous-reviews strip. | ☐ |
| 3.8 | Tap **Rate this review**. | The matrix opens. Rows = KRAs, columns = months. Self-rating chip shows the employee's score. | ☐ |
| 3.9 | Score a few cells. | Auto-save indicator flushes within a few seconds. | ☐ |
| 3.10 | Resize the window or test on a phone vs a tablet. | Table on tablet/desktop, accordion on phone (responsive at 720 px). | ☐ |
| 3.11 | Add an overall manager comment. | The running weighted total in the footer updates. | ☐ |
| 3.12 | Fill all cells, tap **Review → Submit**. | All valid → `/rate/success` clean screen. | ☐ |
| 3.13 | Leave one cell blank and try to submit. | Submit is gated, OR if the server accepts a partial → `/rate/partial` lists which months/KRAs are still pending. | ☐ |
| 3.14 | Open a review whose deadline has already passed. | A permissions banner is shown; the screen is read-only. A deadline-warning card appears when the deadline is near. | ☐ |
| 3.15 | In bulk-select mode, pick several reviews → **Bulk Approve**. | `/bulk-approve/result` splits Approved vs Skipped with reasons (already-rated / not-yet-self-rated / validation-failed). | ☐ |
| 3.16 | Switch the top mode to **My Review** and self-rate your own KRAs. | The employee self-rate screens are reused. | ☐ |
| 3.17 | Open Team History. Filter by employee / cycle. Tap a row. | Paginated history; tap opens a read-only historical review. | ☐ |
| 3.18 | Open Profile. | Read-only summary with sign-out. | ☐ |

---

## 7. Phase 4 — HR Admin: Finalise & Pay Out

Sign back in as HR Admin. **First repeat Phases 2 & 3 for May, then for June.** Only then run this phase.

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| 4.1 | Open HR Home after the manager has rated. | Pipeline funnel counts move (Self-Rated → Manager-Rated). KPIs / action items update. | ☐ |
| 4.2 | Open Reports → **Audit Log**. Filter by date and look at the most recent entries. | Manager rate actions and bulk approvals appear. | ☐ |
| 4.3 | As employee/manager, check the history strip on Home after a cycle has progressed. | Their tile shows the right state and (if rated) the final score. | ☐ |

> **Known unbuilt (don't file bugs)**: cycle close, payout summary, score-distribution reports, payout export, closed-cycle read-only enforcement. These are backend + UI work scheduled for a later step. The Audit Log is the only Reports entry that's currently live.

---

## 8. Cross-cutting checks (apply in every phase)

These behaviours aren't tied to one screen. Test them opportunistically.

| # | Action | Expected | ✓ |
|---|--------|----------|---|
| X.1 | Watch any async screen during initial load. | Shimmer placeholders sized like the real content. | ☐ |
| X.2 | Force a network error on a read (turn airplane mode on during a refresh). | A friendly message + Retry button. Tapping Retry re-fetches. | ☐ |
| X.3 | Open a screen with no data (empty employee list, empty audit log on a fresh env). | Empty-state illustration + one-line message + a CTA where relevant. | ☐ |
| X.4 | On any paginated list, pull to refresh, scroll to load more, navigate away and back. | Pull-to-refresh works. Shimmer rows appear while loading more. Scroll position is preserved when you come back. | ☐ |
| X.5 | Toggle the device offline. | A thin grey strip appears at the top of the screen with "You're offline". | ☐ |
| X.6 | While offline, attempt a write (e.g. create an employee). | The write fails immediately with a friendly message. There is **no offline mutation queue** — this is the current limitation. | ☐ |
| X.7 | Find any currency amount. | Renders in Indian format: `₹1,37,835.00`. | ☐ |
| X.8 | Find any date. | Renders as e.g. `12 May 2026` — no time, no comma. | ☐ |
| X.9 | Scan colours across screens. | Primary purple `#6B1F7C`, accents orange `#FF6B1A` / yellow `#FFB800` / red `#E63946`. Plus Jakarta Sans font throughout. | ☐ |
| X.10 | Sign out from any role / any tab. | Returns immediately to `/login`. | ☐ |
| X.11 | Confirm any destructive action (delete location, remove KRA, deactivate employee). | A red **ConfirmActionDialog** asks first. Cancel cancels. | ☐ |
| X.12 | Find the offline-banner during a network drop, then come back online. | The banner disappears. Data calls resume. | ☐ |

---

## 9. Known issues — do NOT file as bugs

### 9.1 Known backend issues

- **Backend RBAC leak on six HR resource paths** — `/employees`, `/kra-templates`, `/review-cycles`, `/locations`, `/kra-assignments`, `/bonus-slabs` return 200 with full data when called with a Manager token; should return 403. Tracked in [docs/BACKEND_RBAC_FINDINGS.md](docs/BACKEND_RBAC_FINDINGS.md). Pure backend bug — the Flutter app gives no UI path to this leak, so it won't surface in normal manual testing. If a backend tester sees a Manager-token request returning HR data, that's expected on the current build until the backend fix lands.
- **`/employees` returns `passwordHash`** — even for HR_ADMIN. Critical backend issue; do not log or screenshot the response body. See same document.
- **Slug vs UUID** on the test env: cycle writes can return 400 because the env seeds with slug IDs (`cyc_q1_fy2627`) but write validators expect UUIDs. Backend issue, not an app bug.

### 9.2 Known unbuilt features

These have been verified by dev as not implemented yet. If you hit them, note them on your sign-off sheet but **do not** create a defect ticket.

- **Phase 4 close-cycle** flow (cycle status never flips to CLOSED).
- **Phase 4 Reports**: payout summary, score-distribution, export. Audit Log is the only real entry.
- **Bulk Setup wizard** (`/hr/bulk-setup`) — currently a stub.
- **Employee detail "Assigned KRA template" display + "View History"** action.
- **Employees screen: Location filter chip** (Role and Active are live).
- **Team list filter axes for location + score band** (only review-state chips are live).
- **Long-press → bulk-select** on the team list (use the AppBar checklist icon instead).
- **Reporting tree to CEO** — currently shows only one level (you + your manager).
- **Photo / photoUrl edit on Profile** — phone is the only editable field.
- **Offline mutation queue** — writes during a network drop are not queued.
- **HR home "Needs your attention" badge** in the AppBar (the action-items section in the body works).
- **App version label** on profile screens.

---

## 10. Severity guide

When you do file a bug, use this scale to set severity. PM will adjust priority separately.

| Severity | Definition | Example |
|----------|------------|---------|
| **Blocker** | The phase can't be completed at all. Major data corruption. Auth loop. App crash on launch. | "Sign In always 500s." / "Tapping any employee crashes the app." |
| **Critical** | Core flow is broken for at least one role but a workaround exists, OR data is wrong. | "Manager rate submit succeeds but the employee sees the old score." |
| **Major** | A whole screen / feature is unusable, with no workaround at the screen-level. | "Self-rate slider doesn't move on Android." |
| **Minor** | One control or one validation is wrong; visible UX bug; workaround exists. | "Role chip shows 'Hr Admin' instead of 'HR Admin'." |
| **Cosmetic** | Spacing, copy, color tint, alignment. | "Active chip icon is off-center by 1 px." |

Tag every ticket with **role**, **screen**, and **build commit**.

---

## 11. Sign-off

At the end of a full test run, a tester should be able to say one of:

- **PASS** — every case in §3 – §8 is ticked, and the known-unbuilt list in §9 was not extended.
- **PASS with notes** — all cases tick, plus a short list of cosmetic/minor defects filed for the next sprint.
- **FAIL** — one or more cases failed at severity Major or above, blocking release.

Sign your name, the build commit (`git rev-parse --short HEAD`), and the date at the bottom of your sign-off sheet.

---

## 12. Running the automated suite (sanity check)

Before you start manual testing, the automated suite should be green. If it's red, the build is unfit for testing.

```bash
flutter pub get
flutter analyze        # expect: No issues found
flutter test           # expect: All tests passed!
```

If the suite is red, file a Blocker against dev and **do not** start manual testing.
