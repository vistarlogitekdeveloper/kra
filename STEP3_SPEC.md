Build the complete Employee module for Vistar KRA & Incentive Management — Step 3. Steps 1 (auth) and 2 (HR admin) are DONE; you are EXTENDING the existing Flutter app. Do not modify or break anything in lib/features/auth/ or lib/features/hr/ or lib/core/.

═══════════════════════════════════════════════════════════════════
EXISTING APP — DO NOT MODIFY
═══════════════════════════════════════════════════════════════════

Already in place:
- flutter_riverpod ^2.4.9, go_router ^13.0.0, dio ^5.4.0
- flutter_secure_storage, shimmer ^3.0.0, connectivity_plus ^5.0.2
- google_fonts (Plus Jakarta Sans), intl ^0.19.0
- AppColors palette (primaryPurple #6B1F7C, accents orange/yellow/red)
- ApiError + AuthException + AsyncValueView + PagedListView + AppRoutes
- ConfirmActionDialog, EmptyState, ErrorState, CurrencyText, DateText, RelativeTimeText, DecimalField
- Shimmer skeletons: DashboardCardSkeleton, ListItemSkeleton, ProfileHeaderSkeleton, KraTableSkeleton, FullScreenLoadingSkeleton
- Existing UserRole enum (extend if needed)
- ConnectivityWrapper

The placeholder employee dashboard at /employee currently exists. Replace it with the full Employee shell while keeping all other roles' placeholders untouched.

═══════════════════════════════════════════════════════════════════
ROLE-BASED ACCESS
═══════════════════════════════════════════════════════════════════

The /employee/* tree is for users with role EMPLOYEE, MANAGER, OPS, FINANCE, HR, HR_ADMIN, BD_MANAGER, WAREHOUSE_MGR — i.e. ALL roles use the Employee module to rate themselves on their own KRAs (an HR person is also an employee). Only ADMIN role might skip this.

Route guard: any logged-in user can access /employee/*. The backend filters by employeeId from the token.

═══════════════════════════════════════════════════════════════════
BACKEND API CONTRACT (USE EXACTLY)
═══════════════════════════════════════════════════════════════════

Same envelope: { success, data, meta? } or { success, error: { code, message } }
All endpoints require Authorization: Bearer <accessToken>
Decimals come as strings ("7000.00")
Dates as ISO 8601

──────── Employee Dashboard ────────
GET /api/v1/employee/dashboard
Returns:
{
  "user": { "id", "name", "employeeCode", "email", "role", "grade",
            "manager": { "id", "name" } | null,
            "projectLocation": { "id", "name" } | null },
  "activeCycle": { "id", "name", "status", "fyLabel", "quarterNum",
                   "startDate", "endDate",
                   "selfRatingDeadline", "managerReviewDeadline",
                   "currentMonth": { "id", "monthLabel", "monthDate", "status" } } | null,
  "currentReview": {
    "id", "state", "monthId",
    "selfRatingComplete": boolean,
    "managerReviewComplete": boolean,
    "opsScoreComplete": boolean,
    "financeScoreComplete": boolean,
    "isFinalized": boolean,
    "selfTotal": "75.00" | null,
    "managerTotal": "73.00" | null,
    "finalTotal": "76.50" | null
  } | null,
  "incentive": {
    "monthlyEligible": "7000.00",
    "quarterlyEligible": "21000.00",
    "earnedSoFar": "15925.00",
    "earnedPercentage": "75.83"
  },
  "deadlinesAlert": {
    "selfRatingDaysRemaining": 5,
    "isOverdue": false
  } | null
}

──────── My KRA Assignments ────────
GET /api/v1/employee/kra-assignments?cycleId=
Returns array of:
{
  "id", "cycleId", "employeeId", "templateId", "isLocked",
  "items": [
    { "id", "category", "name", "description", "target", "trackingMethod",
      "weightage": "0.05", "defaultMaxScore": 10, "scoreSource", "sortOrder" }
  ],
  "cycle": { "id", "name", "status" },
  "template": { "id", "name", "role" } | null
}

──────── My Reviews ────────
GET /api/v1/employee/reviews?cycleId=
Returns paginated list of:
{
  "id", "cycleId", "monthId",
  "month": { "id", "monthLabel", "monthDate", "status" },
  "state": "DRAFT|SELF_RATED|MANAGER_REVIEWED|OPS_SCORED|FINANCE_SCORED|FINALIZED",
  "selfRatedAt", "managerReviewedAt", "finalizedAt",
  "selfTotal", "managerTotal", "finalTotal",
  "isLocked"
}

GET /api/v1/employee/reviews/:reviewId
Returns single review with full scores:
{
  "id", "cycleId", "monthId", "state", "isLocked",
  "self": {
    "ratedAt", "comment",
    "scores": [
      { "assignmentItemId", "itemName", "weightage": "0.05",
        "maxScore": 10, "score": "8.5", "comment": "...",
        "weightedScore": "0.425" }
    ],
    "total": "75.00"
  } | null,
  "manager": {
    "reviewedAt", "reviewerName", "comment",
    "scores": [...],
    "total": "73.00"
  } | null,
  "ops": { /* same shape */ } | null,
  "finance": { /* same shape */ } | null,
  "final": {
    "finalizedAt", "total": "76.50",
    "incentiveAmount": "5325.00"
  } | null
}

──────── Submit Self-Rating ────────
POST /api/v1/employee/reviews/:reviewId/self-rate
Body:
{
  "comment": "Optional overall comment for the month",
  "scores": [
    { "assignmentItemId": "uuid", "score": 8.5, "comment": "Met all SLAs" },
    ...
  ]
}
Validates:
- reviewState must currently be DRAFT
- month.status must be OPEN
- selfRatingDeadline must not have passed (server checks)
- All assignmentItems must have a score
- Each score must be 0 ≤ score ≤ defaultMaxScore for that item
Response 200: updated review with state=SELF_RATED, calculated total
Errors:
- 409 REVIEW_ALREADY_RATED if state != DRAFT
- 409 MONTH_LOCKED if month.status == LOCKED
- 409 DEADLINE_PASSED if past deadline
- 400 SCORE_OUT_OF_RANGE if any score is invalid
- 400 INCOMPLETE_SCORES if any item missing

──────── Update Self-Rating (only if not yet manager-reviewed) ────────
PATCH /api/v1/employee/reviews/:reviewId/self-rate
Same body, same validations except state can be SELF_RATED.
409 if state has progressed past SELF_RATED.

──────── Incentive Summary ────────
GET /api/v1/employee/incentive-summary?cycleId=
Returns:
{
  "cycleId", "cycleName",
  "monthlyEligible": "7000.00",
  "quarterlyEligible": "21000.00",
  "earnedSoFar": "15925.00",
  "earnedPercentage": "75.83",
  "monthlyBreakdown": [
    { "monthId", "monthLabel", "monthDate",
      "reviewState", "finalScorePct": "82.50",
      "earnedAmount": "5775.00", "isFinalized": true }
  ]
}

──────── Profile ────────
GET /api/v1/employee/profile
Returns full Employee object (same shape as in HR module).

──────── Update Own Profile (limited fields) ────────
PATCH /api/v1/employee/profile
Body: { phone?, photoUrl? }
(name, email, role, etc. are HR-only edits)

═══════════════════════════════════════════════════════════════════
WHAT TO BUILD — 4 SECTIONS UNDER EMPLOYEE SHELL
═══════════════════════════════════════════════════════════════════

A nested-route shell with bottom navigation (4 tabs):
1. Home — personal dashboard with current cycle, KRA list, history strip, incentive
2. Self-Rate — current month rating form (the most-used screen)
3. History — all my past reviews with detail drill-down
4. Profile — view/edit own info, see manager + reporting tree

═══════════════════════════════════════════════════════════════════
NEW FOLDER STRUCTURE
═══════════════════════════════════════════════════════════════════

```
lib/features/employee/
├── data/
│   ├── models/
│   │   ├── employee_dashboard.dart        # full GET /dashboard response
│   │   ├── my_kra_assignment.dart         # list item from /kra-assignments
│   │   ├── my_review_summary.dart         # list item from /reviews
│   │   ├── my_review_detail.dart          # full GET /reviews/:id
│   │   ├── kra_score_entry.dart           # one row in self-rate form
│   │   ├── self_rate_request.dart         # POST body
│   │   ├── incentive_summary.dart         # full GET /incentive-summary
│   │   ├── monthly_incentive.dart         # one row in monthlyBreakdown
│   │   └── enums.dart                     # ReviewState (DRAFT/SELF_RATED/...etc)
│   │
│   └── repositories/
│       ├── employee_dashboard_repository.dart        (interface)
│       ├── api_employee_dashboard_repository.dart
│       ├── my_kra_repository.dart
│       ├── api_my_kra_repository.dart
│       ├── my_review_repository.dart
│       ├── api_my_review_repository.dart
│       ├── self_rate_repository.dart
│       ├── api_self_rate_repository.dart
│       ├── my_incentive_repository.dart
│       ├── api_my_incentive_repository.dart
│       ├── my_profile_repository.dart
│       └── api_my_profile_repository.dart
│
└── presentation/
    ├── providers/
    │   ├── employee_dashboard_providers.dart
    │   ├── my_kra_providers.dart
    │   ├── my_review_providers.dart
    │   ├── self_rate_providers.dart
    │   ├── my_incentive_providers.dart
    │   └── my_profile_providers.dart
    │
    ├── screens/
    │   ├── employee_shell_screen.dart      # bottom nav scaffold
    │   │
    │   # HOME
    │   ├── home/
    │   │   ├── employee_home_screen.dart
    │   │   ├── widgets/
    │   │   │   ├── greeting_header.dart           # time-aware greeting
    │   │   │   ├── current_month_card.dart        # big CTA — "Start rating" or "Submitted"
    │   │   │   ├── deadline_banner.dart           # appears if ≤3 days
    │   │   │   ├── my_kras_summary_card.dart      # collapsed KRA list
    │   │   │   ├── history_strip.dart             # horizontal scroll of last 6 months
    │   │   │   └── incentive_snapshot_card.dart   # eligible / earned / progress
    │   │
    │   # SELF-RATE
    │   ├── self_rate/
    │   │   ├── self_rate_screen.dart       # main form
    │   │   ├── self_rate_review_screen.dart # before-submit summary
    │   │   ├── self_rate_success_screen.dart # post-submit confirmation
    │   │   ├── self_rate_locked_screen.dart  # if already submitted/locked
    │   │   └── widgets/
    │   │       ├── kra_score_input_card.dart    # one card per KRA
    │   │       ├── score_slider.dart             # 0 to maxScore with steps
    │   │       ├── weightage_progress_bar.dart   # shows current weighted total preview
    │   │       ├── month_picker_chip.dart
    │   │       └── self_rate_submit_bar.dart     # sticky bottom: total + submit
    │   │
    │   # HISTORY
    │   ├── history/
    │   │   ├── my_reviews_history_screen.dart
    │   │   ├── review_detail_screen.dart        # full breakdown for one month
    │   │   └── widgets/
    │   │       ├── review_history_card.dart      # state badge + scores at-a-glance
    │   │       ├── review_state_badge.dart       # pill for ReviewState enum
    │   │       ├── score_comparison_table.dart   # self/manager/ops/finance/final per item
    │   │       └── score_progression_chart.dart  # visual: self→manager→final per item
    │   │
    │   # PROFILE
    │   ├── profile/
    │   │   ├── my_profile_screen.dart
    │   │   ├── edit_profile_screen.dart      # phone, photo only
    │   │   ├── my_reporting_tree_screen.dart # see my manager + my reports if any
    │   │   └── widgets/
    │   │       ├── profile_header.dart
    │   │       ├── profile_field_row.dart
    │   │       └── my_manager_card.dart
    │
    └── widgets/
        ├── review_state_badge.dart      # shared across home + history
        ├── deadline_chip.dart           # color-coded by days remaining
        ├── score_pill.dart              # small "8.5/10" chip
        └── empty_my_dashboard.dart      # if no active cycle assigned
```

═══════════════════════════════════════════════════════════════════
ROUTING — UPDATE app_router.dart
═══════════════════════════════════════════════════════════════════

Use StatefulShellRoute.indexedStack for /employee just like HR:

```
/employee (EmployeeShellScreen)
  Branch 1: /employee/home → EmployeeHomeScreen
  Branch 2: /employee/self-rate → SelfRateScreen
            /employee/self-rate/review → SelfRateReviewScreen
            /employee/self-rate/success → SelfRateSuccessScreen
            /employee/self-rate/locked → SelfRateLockedScreen
  Branch 3: /employee/history → MyReviewsHistoryScreen
            /employee/history/:reviewId → ReviewDetailScreen
  Branch 4: /employee/profile → MyProfileScreen
            /employee/profile/edit → EditProfileScreen
            /employee/profile/reporting-tree → MyReportingTreeScreen
```

After login, every role EXCEPT ADMIN routes to /employee/home as their default. (HR_ADMIN can switch to HR shell from a "View as HR Admin" button in the profile/drawer — design detail for later, not Step 3.)

═══════════════════════════════════════════════════════════════════
HOME SCREEN — DETAILED SPEC
═══════════════════════════════════════════════════════════════════

Layout (top to bottom, scrollable, pull-to-refresh):

1. **Greeting header** (no card)
   - "Good morning, Pravin" (time-aware: morning <12, afternoon <17, evening <21, night)
   - Subtitle: today's date + employeeCode small + role pill

2. **Deadline banner** (only if selfRatingDaysRemaining ≤ 3)
   - Slides down from top, accentOrange background if ≤3 days, red if overdue
   - Message: "Self-rating closes in 2 days" or "Self-rating overdue — submit now"
   - Tap → navigate to /employee/self-rate

3. **Current month card** — uses dashboard.currentReview
   - Large card, brand gradient if action needed, surface white if done
   - Variants based on state:
     - **DRAFT** + month OPEN: "April 2026 • Self-rating pending" + "Start rating →" CTA button
     - **SELF_RATED**: "April 2026 • Self-submitted ⏳ Awaiting manager" + view-only "View my submission"
     - **MANAGER_REVIEWED**: "April 2026 • Manager reviewed: 73/100" + "View details"
     - **FINALIZED**: "April 2026 • Final: 76.5/100 • ₹5,325 earned" + green check icon
     - No active cycle: empty state with illustration "No active review cycle"

4. **My KRAs summary card**
   - Title "My KRAs (10 items)" + subtitle "Q2 FY 2026-27 • {template name}"
   - Show first 4 items as compact rows (name + weightage chip)
   - "View all" button if more than 4 → expandable inline OR navigate to KRA detail screen
   - If no assignments: empty state "No KRAs assigned for this cycle. Contact HR."

5. **History strip** — horizontal scrollable
   - Last 6 months of reviews as compact chips
   - Each chip: month label + state badge + final score (or "Pending" if not finalized)
   - Tap → navigate to /employee/history/:reviewId

6. **Incentive snapshot card** — uses dashboard.incentive
   - "My incentive this quarter"
   - Big number: ₹15,925 (earnedSoFar) of ₹21,000 (quarterlyEligible)
   - Progress bar showing earnedPercentage (75.83%)
   - Subtitle: "Based on finalized reviews. Subject to change."
   - Tap → navigate to /employee/history (full breakdown there)

═══════════════════════════════════════════════════════════════════
SELF-RATE SCREEN — THE MOST CRITICAL UI
═══════════════════════════════════════════════════════════════════

Flow: 3 steps via separate screens, but shared state via SelfRateNotifier.

**Step 1: SelfRateScreen (main form)**
- AppBar: "Rate yourself — April 2026" + close button
- Top sticky: WeightageProgressBar showing live weighted total (e.g. "Current total: 7.6/10")
- Body: scrollable list of KraScoreInputCards, one per KRA item
- Each card:
  - KRA name (16px bold) + category chip + weightage badge ("5%")
  - Description (collapsed, expandable on tap)
  - Target text + tracking method text in muted typography
  - **ScoreSlider**: 0 to defaultMaxScore, integer steps, large draggable thumb, current value displayed prominently (e.g. "8.5/10")
  - Score comment (optional multiline text field, 200 char limit, char counter)
  - Card border color: gray default, accentOrange if missing score, success green if filled
- Bottom sticky: SelfRateSubmitBar
  - Left: "Total: 76.5/100" weighted total
  - Right: "Review →" button (primary), disabled until ALL items have a score
- Save Draft mechanism: auto-save to local storage every 5 seconds while editing (prevents data loss). Use SharedPreferences (NOT secure storage — these aren't secrets).
- On exit attempt with unsaved changes: ConfirmActionDialog "You have unsaved changes. Save as draft and exit?" — YES saves locally, NO discards, CANCEL stays.

**Step 2: SelfRateReviewScreen (pre-submit summary)**
- Read-only summary table of all KRAs with scores
- Highlights any items with comments (flag icon)
- Shows weighted total prominently at top
- Optional overall comment field at bottom (multiline)
- Two buttons: "Back to edit" (secondary) and "Submit final" (primary destructive style — "this is final" feeling)
- Submit triggers POST with full payload, shows loading overlay

**Step 3: SelfRateSuccessScreen**
- Full-screen success illustration
- "Submitted! Your manager will review by [managerReviewDeadline]"
- "Total submitted: 76.5/100"
- "View submission" button → navigates to history detail
- "Back to home" button

**Step 4: SelfRateLockedScreen** (shown if user navigates to /self-rate when already submitted or locked)
- Read-only view of submitted scores
- Reason banner: "You submitted on April 5, 2026 — awaiting manager review"
- Or: "Self-rating period closed on April 5, 2026"
- "View submission" CTA → review detail

═══════════════════════════════════════════════════════════════════
HISTORY SCREEN — DETAILED SPEC
═══════════════════════════════════════════════════════════════════

**List screen:**
- Filter chips at top: All / Pending / Finalized
- Cycle filter dropdown if multiple cycles in history
- List of ReviewHistoryCards in reverse chronological order
- Each card:
  - Month label (e.g. "April 2026") + ReviewStateBadge
  - Three score chips in row: Self · Manager · Final (whichever exist, others show "—")
  - Earned amount in success green if finalized
  - Chevron → tap to detail
- Empty state if no history yet

**Detail screen — ReviewDetailScreen:**
- AppBar: month label + cycle name as subtitle
- ReviewStateBadge prominently at top with timeline indicator showing current step (5 dots: DRAFT → SELF_RATED → MANAGER → OPS → FINANCE → FINALIZED, current step highlighted)
- ScoreComparisonTable: rows = KRA items, columns = Self / Manager / Ops / Finance / Final
  - Each cell shows score + weighted score + comment indicator
  - Long-press cell → bottom sheet with full comment text
- Total row at bottom (column-aligned totals)
- If FINALIZED: "Incentive earned: ₹5,325" highlighted card at bottom
- If user can still edit (state == SELF_RATED, manager not yet reviewed): "Edit submission" button at bottom

═══════════════════════════════════════════════════════════════════
PROFILE SCREEN — DETAILED SPEC
═══════════════════════════════════════════════════════════════════

**My Profile:**
- ProfileHeader: avatar (initials in colored circle, color derived from employeeCode hash) + name + role pill + employeeCode
- Info sections:
  - Contact: email (read-only), phone (editable), grade (read-only)
  - Reporting: manager card (tap → reporting tree), location card
  - Defaults: defaultTemplate name, monthlyIncentiveAmount
- Edit button → /employee/profile/edit (only phone + photo editable)
- "Logout" button at bottom (destructive style)

**Edit Profile:**
- Phone field with format validation
- Photo picker (placeholder if not implemented yet — show "Coming soon")
- Save button only enabled when changed

**My Reporting Tree:**
- Vertical chain showing my manager(s) above me
- My direct reports below me (if I have any — e.g. a Manager role user)
- Each node tappable to view that person's profile (limited view — name + role + employeeCode only)

═══════════════════════════════════════════════════════════════════
PRODUCTION STANDARDS — APPLY ALL
═══════════════════════════════════════════════════════════════════

1. **Auto-save draft** in self-rate form every 5 seconds (SharedPreferences, key per reviewId)
2. **Resume draft** on screen open: if local draft exists for current reviewId, prompt "Resume your draft from {time ago}?"
3. **Discard draft** automatically once submitted successfully
4. **Optimistic UI** on profile edit (revert on error)
5. **Pull-to-refresh** on home, history, profile
6. **Shimmer skeletons** on every loading state — use existing primitives. Self-rate uses KraTableSkeleton during load.
7. **Pagination** on history list (20 per page)
8. **All errors** mapped via existing ApiError → user-friendly snackbars
9. **Currency formatting** Indian style throughout (CurrencyText widget)
10. **Date formatting** "12 May 2026" (DateText widget)
11. **Score validation** client-side: 0 ≤ score ≤ maxScore, surface "Score must be between 0 and 10" as inline help
12. **Decimal handling**: backend sends/receives as strings. Score input UI accepts decimals like 8.5, sends as number.
13. **Confirm dialogs** before submitting self-rating ("Once submitted, you cannot change this until manager reviews")
14. **Connectivity wrapper** — submit button disabled when offline, with tooltip "Internet required to submit"
15. **Keyboard handling** in self-rate: when focusing a comment field, scroll the card into view above the keyboard
16. **No magic strings/colors**
17. **AsyncValue.when complete cases** everywhere via AsyncValueView
18. **Empty states** for: no active cycle, no KRAs assigned, no history yet
19. **Performance**: const constructors, ListView.builder for history, debounced auto-save

═══════════════════════════════════════════════════════════════════
HARD REQUIREMENTS RECAP
═══════════════════════════════════════════════════════════════════

1. ✅ All 6 repository interfaces + Dio implementations matching API contract
2. ✅ All ~9 model classes with fromJson/toJson/copyWith and decimal-string handling
3. ✅ All 6 Riverpod provider files
4. ✅ EmployeeShellScreen with StatefulShellRoute (4 tabs)
5. ✅ Home with all 6 sections, independent shimmer + error per section
6. ✅ Self-rate flow: 4 screens (form, review, success, locked) with shared state
7. ✅ Auto-save draft to SharedPreferences every 5 seconds
8. ✅ Resume draft prompt on re-open
9. ✅ History list with filters + detail with comparison table
10. ✅ Profile view + limited edit + reporting tree
11. ✅ All API errors mapped to friendly messages
12. ✅ All forms validate client-side, surface server errors per-field
13. ✅ Confirm dialogs on irreversible actions
14. ✅ Empty states + error states everywhere
15. ✅ Indian currency + date formatting
16. ✅ Connectivity-aware submit
17. ✅ Score sliders work cleanly with decimal scores
18. ✅ Pull-to-refresh on all main screens
19. ✅ All AsyncValue states handled
20. ✅ All strings in app_strings.dart, all colors in AppColors

═══════════════════════════════════════════════════════════════════
OUTPUT FORMAT
═══════════════════════════════════════════════════════════════════

Generate every file in full. After all code, provide:

1. Updated pubspec.yaml (add shared_preferences ^2.2.2 if not already present)
2. Updated app_strings.dart with all new Employee module strings appended under // ─── Employee Module ─── section
3. Updated app_router.dart with full Employee shell routes via StatefulShellRoute, AND update post-login redirect logic to send all non-ADMIN roles to /employee/home by default
4. A test checklist:
   - Login as Employee (Pravin VLPL0003) → lands on /employee/home with shimmer then real data
   - Current month card shows "Start rating →" CTA when state==DRAFT
   - Tap CTA → self-rate form opens with all assigned KRAs
   - Enter scores for 3 of 10 items, navigate away → return → "Resume draft from 30 seconds ago?" prompt appears, accept → scores restored
   - Try to submit with 1 KRA missing score → submit button disabled
   - Fill all scores → tap "Review" → review screen shows summary
   - Submit → success screen → return to home → current month card now shows "Submitted ⏳ Awaiting manager"
   - Try /employee/self-rate again → SelfRateLockedScreen shown
   - History tab → see latest review with SELF_RATED badge
   - Tap into history detail → comparison table shows my scores in Self column, others empty
   - Profile tab → see all info; tap edit → only phone editable; save phone → optimistic update
   - Reporting tree → see manager Amol Veer above me
   - Lose internet → submit button disabled with tooltip
   - Manager (different test account, different role) logs in → also lands on /employee/home (because manager rates themselves too)
   - HR_ADMIN logs in → still lands on /employee/home by default (will add HR shell switcher later)
   - Try POSTing past the deadline (mock the date) → 409 error mapped to "Self-rating period has closed for this month"

5. A note on what Step 4 (Manager module) will need from this — specifically, the manager will fetch /manager/team-reviews and call /manager/reviews/:id/manager-rate which mirrors the self-rate API but on the manager side.

DO NOT abbreviate. DO NOT skip files. The output should be production-ready and runnable with `flutter pub get && flutter run`.