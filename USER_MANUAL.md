# Vistar KRA — User Manual

**Vistar KRA & Incentive Management** is the company-wide app for setting goals, reviewing performance, and paying out the incentive that follows. Every Vistar employee uses it; the surface they see depends on their role.

This manual walks through the app the way a real user moves through it: what they see when they open it, what they can do on each screen, and where they go next.

---

## 1. The 30-second mental model

The app runs on a quarterly **review cycle**. Inside a cycle there are three things that happen, in order, every month:

| Phase                | Who acts             | What they do                                                                  |
| -------------------- | -------------------- | ----------------------------------------------------------------------------- |
| **Self-rate**        | Employee             | Scores themselves on each KRA for the month, with a one-line comment per KRA. |
| **Manager rate**     | Reporting manager    | Reviews the employee's self-rating, sets the final score, adds comments.      |
| **HR finalise**      | HR Admin             | Locks the cycle, runs payouts based on the per-employee performance incentive.                        |

Everything else in the app — KRA Templates, Locations, Employees, Reports — exists to feed those three actions.

---

## 2. Roles and what they see

The app picks the landing screen automatically based on the role on the user record. There is no role-picker on the login screen.

| Role                                        | Lands at                       | Bottom-nav tabs                                    |
| ------------------------------------------- | ------------------------------ | -------------------------------------------------- |
| `HR_ADMIN`, `HR`, `ADMIN`                   | `/hr/home`                     | Home · Employees · Templates · Cycles · Reports    |
| `MANAGER`, `BD_MANAGER`, `WAREHOUSE_MGR`    | `/manager/team/dashboard`      | Dashboard · Team · History · Profile               |
| `EMPLOYEE`, `OPS`, `FINANCE`                | `/employee/home`               | Home · Self-Rate · History · Profile               |

Manager-capable roles can still self-rate — they switch into "My Review" mode from the top of the manager shell, which reuses the employee screens for their own KRAs. `HR_ADMIN` can also drop into the manager surface for escalations.

If a user deep-links to a route they aren't allowed to see (for example an employee tapping a notification that goes to `/hr/employees`), the router redirects them to their own dashboard. If they hit a deep-link the app doesn't have a screen for, they get the friendly **"This page isn't ready yet"** screen with a working **Go to Home** button.

---

## 3. Logging in

**Screen:** `/login`

1. Open the app. The Vistar logo loads, the auth state restores from secure storage. If a token is still valid, the user is taken straight to their role's dashboard.
2. Enter **Employee ID** (e.g. `VLPL0610`) and password. Both fields are required.
3. Tap **Sign In**. A spinner appears in the button; the screen stays put while the request is in flight.
4. On success, the router pushes the user to their role's home screen.
5. On failure, an inline error appears under the form (wrong credentials, network error, server down).

Tokens live in `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences on Android). They never touch `SharedPreferences`.

A 401 from any later request auto-logs the user out and sends them back to login.

---

## 4. HR Admin flow

The HR Admin owns the lifecycle: hiring people, defining what they're measured on, opening the cycle, watching progress, paying out.

### 4.1 HR Home `/hr/home`

A scrolling dashboard with eight sections, each fetched independently:

1. **Overview cards** — total active employees, locations, open cycles.
2. **Active cycle card** — current quarter, dates, status (Open / Closed).
3. **KPIs** — submission rate, average score, on-time %.
4. **Pipeline funnel** — Self-Rated → Manager-Rated → HR-Approved counts.
5. **Action items** — "5 employees haven't submitted", "3 reviews need HR override".
6. **Location heatmap** — score by location, colour-coded. Tap a location to filter.
7. **Recent activity** — last 15 actions across the org (audit log preview).
8. **Deadlines** — countdown strip for cycle close, payout, etc.

**Pull down to refresh** invalidates all eight providers; sections stay cached across scrolls so the dashboard doesn't re-fetch every time a card scrolls off-screen.

**"Needs your attention" badge** in the app bar opens the action-items section. Some entries deep-link to specific employees or reviews; some go to backend-only pages the app doesn't render — those land on the friendly fallback screen.

### 4.2 Employees `/hr/employees`

A paginated, searchable list of every employee in the org.

- **Search box** filters by name / employee code as you type.
- **Filter chips** — by Location, by Role, by Active/Inactive.
- **List tile** — name, role, location, current cycle status.
- **+ button** (top-right) → `/hr/employees/new` → Employee Form.
- **Tap a row** → `/hr/employees/:id` → Employee Detail.

#### 4.2.1 Employee Detail `/hr/employees/:id`

Shows the employee's profile (read-only), assigned KRA template, current cycle status, and reporting manager.

- **Edit** → `/hr/employees/:id/edit` (same form as creation, pre-filled).
- **Assign KRA** → jumps to KRA Assign with this employee pre-selected.
- **View history** → all their past reviews (HR view).

#### 4.2.2 Employee Form `/hr/employees/new` (or `/edit`)

Fields:
- Name, Employee Code, Email, Phone
- Role (dropdown from the canonical role list)
- Location (dropdown from Locations)
- Reporting Manager (typeahead against active managers)
- Active toggle

**Save** → POST or PATCH, back to the list. Validation is client-side (required fields, email regex), the server enforces uniqueness.

### 4.3 KRA Templates `/hr/kra-templates`

A KRA Template is a reusable set of measurable goals (e.g. "Regional Manager (Smart Goals)"). Multiple employees can be assigned the same template.

- **List tile** shows template name, KRA count, total weightage. (Counts come from the live backend's `_count.items`; the weightage pill is hidden until full template detail is hydrated.)
- **+ button** → `/hr/kra-templates/new` → Template Form.
- **Tap a row** → `/hr/kra-templates/:id` → edit mode.

#### 4.3.1 KRA Template Form

Top-level fields:
- Template Name
- Description (optional)
- Target Role (which roles this template can be assigned to)

Then the **KRA items** list. Each item has:
- Title (e.g. "Achieve monthly sales target")
- Description / target (e.g. "₹50L per month")
- Weightage (%) — all items in the template must total 100%.
- Display order

**Add KRA** → opens a bottom sheet to enter a new item.
**Tap an existing KRA** → opens the same bottom sheet pre-filled.
**Delete an existing KRA** → a `ConfirmActionDialog` (red variant) appears: "Remove this KRA from the template?" — to protect against an accidental tap that wipes a goal someone might care about.

The footer shows the running total weightage. **Save** is disabled until it equals 100%.

### 4.4 Review Cycles `/hr/cycles`

A cycle is the timebox the whole org rates against (e.g. *Q1 FY26-27, Apr–Jun*).

- **List tile** — cycle name, date range, status, # employees enrolled.
- **+ button** → `/hr/cycles/new` → Cycle Form.
- **Tap a row** → jump into cycle detail / actions.
- **Performance incentive (per employee)** → set on the employee Add/Edit form (`/hr/employees/:id/edit`) — a single monthly incentive amount per employee. Leave blank to fall back to the org default. Used by HR finalise to compute payouts.

#### 4.4.1 Cycle Form

Fields:
- Cycle name (auto-suggested from quarter)
- Start date, End date (date pickers)
- Self-rate deadline, Manager-rate deadline
- Linked KRA templates (which roles/templates participate)

### 4.5 Assign KRA `/hr/assign`

The bridge from Templates → Employees. Pick a template, pick employees (with location/role filters), confirm. Validation prevents assigning more than one active template to the same employee.

### 4.6 Locations `/hr/locations`

The list of physical sites employees report to (warehouses, regional offices). Each location has a name and address.

- **+ button** → bottom sheet to create.
- **Tap a row** → bottom sheet to edit (or delete with confirmation).
- Used everywhere as the canonical address book — Employees, Heatmap, Reports.

### 4.7 Reports `/hr/reports`

Read-only summaries:
- Score distribution by location / role / template.
- Incentive payout summary for any closed cycle.
- **Audit Log** (`/hr/reports/audit-log`) — paginated, filterable by actor / action / entity type / date range. The forensic trail.

### 4.8 Bulk Setup `/hr/bulk-setup`

A guided wizard for setting up a new cycle: pick the cycle, pick locations/roles, auto-assign templates, send notifications. Useful at the start of a quarter.

---

## 5. Manager flow

The Manager's job is small in surface area but high-stakes: rate each report on each KRA each month, fairly and on time.

The manager shell has a **mode switcher at the top** — "My Team" (default) and "My Review" (their own self-rating, reusing the Employee screens).

### 5.1 Manager Dashboard `/manager/team/dashboard`

- **Greeting card** — name, role, today's date.
- **Stats grid** — team size, reviews pending, reviews overdue, team average score.
- **Pending actions list** — every report whose review needs the manager's attention this month, sorted by deadline. Each tile shows employee name, KRA cycle, days remaining (or "OVERDUE" in red).
  - Tap a tile → review detail for that employee/cycle.
- **Team trend card** — rolling 3-month average of team scores.
- **No-reports empty state** when the manager has no direct reports.

### 5.2 Team `/manager/team/list`

Every direct report, with the latest cycle's state and a 3-month trend strip per row.

- **Filter chips** — by review state (Pending Self-Rate, Pending Manager, Done, Overdue). Location + score-band axes are planned but not yet wired.
- **Bulk select** — tap the checklist icon in the app bar to enter selection mode. The app bar swaps to a count + actions row.
  - Pick multiple reviews → **Bulk Approve** → `/manager/team/bulk-approve?ids=…`.

#### 5.2.1 Team Member Profile `/manager/team/list/:employeeId`

A read-only view of the report: contact info, current KRAs, this cycle's scores, link to **History** for that one person (`/manager/team/list/:employeeId/history`).

### 5.3 Review Detail `/manager/team/reviews/:reviewId`

Shows the employee's submitted self-rating for the active cycle:
- Per-KRA score (1–10) and self-comment for each of the three months in the quarter.
- Weightage and weighted total.
- **Permissions banner** when the cycle deadline has passed (read-only mode).
- **Deadline warning card** when the deadline is near.
- **Previous reviews strip** for context.

**Rate this review** → `/manager/team/reviews/:reviewId/rate`.

### 5.4 Manager Rate `/rate`

The matrix screen. Rows = KRAs, columns = months. The manager fills in their score for every cell, with optional comments.

- **Responsive view** — table view on tablets/desktop, accordion on phone.
- **Self-rating chip** shows what the employee gave themselves; the manager's input lives below.
- **Auto-save indicator** in the app bar — every edit flushes to the backend after a short debounce.
- **Footer** — running weighted total for the month / cycle.
- **Manager comment field** at the bottom for overall comment.
- **Review** button → `/rate/review` (summary screen) → **Submit**.

On submit:
- All cells valid → `/rate/success`.
- Some cells failed validation server-side → `/rate/partial` listing which months/KRAs are still pending so the manager can finish them off.

### 5.5 Bulk Approve

From the team-list bulk-select mode:
1. `/bulk-approve?ids=...` — selection summary. Confirm.
2. The app POSTs each approval in sequence.
3. `/bulk-approve/result` — split into **Approved** and **Skipped** (skipped = already-rated, not-yet-self-rated, validation failed). Each list shows employee + reason.

### 5.6 Team History `/manager/team/history`

All past reviews across the team, paginated. Filter by employee, by cycle. Tap a row → read-only review screen for that historical cycle.

### 5.7 Manager Profile `/manager/team/profile`

The manager's own profile (read-only summary, sign-out button, app version).

---

## 6. Employee flow

Four tabs. Self-rate is where the actual work happens; the rest are context.

### 6.1 Home `/employee/home`

- **Greeting header** with name and current cycle.
- **Deadline banner** — turns yellow/red as the self-rate deadline approaches.
- **Current month card** — month name, status (Not Submitted / Submitted / Approved), CTA button.
- **My KRAs summary card** — quick list of every KRA in the template with weightage.
- **Incentive snapshot card** — projected payout based on the latest score and the per-employee performance incentive.
- **History strip** — last 3 cycles' scores as chips. Tap → History.

### 6.2 Self-Rate `/employee/self-rate`

The form. Per-month, per-KRA scoring:

1. **Month picker chip** at the top — Apr / May / Jun (for a Q1 cycle).
2. For each KRA, a **score input card**:
   - Title and target.
   - **Score slider** (1–10).
   - Optional comment field.
3. **Weightage progress bar** at the top of the screen — turns green when the cycle is complete.
4. **Submit bar** at the bottom — "Review & Submit".

#### 6.2.1 Edge states

- **Locked** (`/self-rate/locked`) — cycle is closed, manager has already rated, or it isn't the user's review window. Read-only message with a "Go to History" CTA.
- **Review** (`/self-rate/review`) — pre-submission summary. Tap each row to jump back and fix.
- **Success** (`/self-rate/success`) — animated checkmark, "Your review has been submitted" + CTA back to Home.

### 6.3 History `/employee/history`

Every past review the employee has done.

- **History card** per cycle — cycle name, date, score, status badge.
- Tap → `/employee/history/:reviewId` → **Review Detail**:
  - Score comparison table (self vs manager).
  - Score progression chart (months × KRAs).
  - Manager comments.

### 6.4 Profile `/employee/profile`

- **Profile header** — photo, name, role, employee code.
- **Field rows** — email (read-only), phone (editable), location, reporting manager.
- **My Manager card** — name + role; tap to call/email.
- **Edit** → `/employee/profile/edit` — only `phone` is exposed in the UI today. The repository would also accept `photoUrl`, but the photo picker is marked "coming soon" on the form. Everything else is HR-owned.
- **Reporting tree** → `/employee/profile/reporting-tree` — visual chain up to the CEO.
- **Sign out** at the bottom.

---

## 7. Cross-cutting behaviour

### 7.1 Loading, errors, empty states

Every async screen uses **AsyncValueView**:
- **Loading** → shimmer placeholders sized like the real content.
- **Error** → friendly message + Retry button (network errors offer Retry; auth errors sign the user out).
- **Empty** → illustration + one-line "Nothing here yet" message with a relevant CTA where possible.

Every paginated list uses **PagedListView** — pull to refresh at the top, shimmer rows at the bottom while the next page loads. List position is preserved when navigating away and back.

### 7.2 Destructive actions

Every delete / remove / discard hits a **ConfirmActionDialog** with the red variant:
- Dialog title states what is being removed.
- Body explains the consequence ("This will remove the KRA from the template. Existing reviews are not affected.").
- Buttons: **Cancel** (grey) and **Remove** (red).

### 7.3 Connectivity

The app listens to `connectivity_plus`. Going offline shows a thin grey strip across the top of the screen. Mutations queue and retry on reconnect; reads fail with a "You're offline" message in the AsyncValueView.

### 7.4 Currency and dates

- Currency renders in Indian format via `intl`: **₹1,37,835.00**.
- Dates render as **12 May 2026** (short month name, no commas, no time).
- All ISO timestamps from the backend are parsed to `DateTime` in the model layer — no string dates in widgets.

### 7.5 Theming

- Primary purple `#6B1F7C`, orange `#FF6B1A`, yellow `#FFB800`, red `#E63946`.
- Typeface: Plus Jakarta Sans (via `google_fonts`).
- One source of truth: `core/constants/app_colors.dart`, `core/constants/app_strings.dart`. Widgets never hardcode either.

### 7.6 Navigation contract

- Every route lives on `AppRoutes` — no raw strings at call sites.
- The router's redirect rules run on every auth-state change, so logging out from any tab returns to `/login` immediately.
- Unknown routes hit the **RouteErrorScreen** with a working "Go to Home" button.
- **Role guards**: `/hr/*` is gated to HR / HR_ADMIN / ADMIN; `/manager/*` is gated to MANAGER / BD_MANAGER / WAREHOUSE_MGR / HR_ADMIN / ADMIN. Deep-links into either area as a non-permitted role are bounced to the user's own dashboard.
- **`/employee/*` is intentionally shared across roles.** Every authenticated user — including managers and HR_ADMIN — uses the employee surface to self-rate their own KRAs (Step 4 spec design). This is not a leak: managers see only their own KRAs because every employee-side endpoint is scoped to `req.user.id` server-side. If you find an employee-side endpoint that returns someone else's data, *that* would be a bug — file it.

### 7.7 Audit log

Every state-changing action in HR Admin (create/edit/delete on employees, templates, cycles, locations; assigning KRAs; closing a cycle; running payouts) writes an audit entry. HR can inspect them in Reports → Audit Log.

---

## 8. End-to-end story: a single quarter

To tie it all together, here is what happens in calendar order in a typical Q1 cycle.

1. **Late March** — HR Admin creates the Q1 FY26-27 cycle (`/hr/cycles/new`), sets per-employee performance incentives on the employee form, runs **Bulk Setup** to auto-assign existing templates to all active employees, opens the cycle.
2. **April 1** — Employees see the new cycle on `/employee/home`. The deadline banner counts down to the April self-rate close.
3. **End of April** — Employees self-rate April (`/employee/self-rate`). The manager dashboard's Pending Actions list grows for each report submitted.
4. **First week of May** — Managers rate April reviews (`/manager/team/reviews/:id/rate`). Reviews flip to "Manager Done" state. Employees see manager scores on `/employee/history/:reviewId`.
5. **May, then June** — Same loop for May, then June.
6. **End of June** — Cycle closes. HR runs the payout summary in Reports, exports it, finance disburses.
7. **History** — Everyone's history strip now shows Q1 FY26-27 with its final score and earned incentive. The cycle is read-only forever.

---

## 9. Test credentials (mock & live backends)

**Mock backend** (offline / unit tests):
- HR_ADMIN — `VLPL0610` / `password123` (Swati Kotkar)

**Live backend** (`https://vistar-crm.onrender.com/api/v1/kra/`) — all passwords `Vistar@123`:

| Role | Email |
|------|-------|
| HR_ADMIN | `hr.admin@vistar.test` |
| MANAGER | `manager@vistar.test` |
| EMPLOYEE | `emp1@vistar.test` (DRAFT) · `emp2@vistar.test` (EMPLOYEE_SUBMITTED_ALL) · `emp3@vistar.test` (FINALIZED) |

The test env currently uses slug IDs for cycles (`cyc_q1_fy2627`) but write validators expect UUIDs — flag any write 400s back to the backend team rather than treating them as app bugs.

---

## 10. Running the app

```bash
flutter pub get
flutter analyze         # must be 0 errors before any commit
flutter run             # picks the connected device/emulator
flutter test            # runs the full suite
```

Current status: **Step 1 (Auth)** and **Step 2 (HR Admin)** are done; **Manager** and **Employee** are wired through. Step 3 employee-side polish is the next major slice.
