Build the complete Manager Module for Vistar KRA & Incentive Management — Step 4. Steps 1 (auth), 2 (HR admin), and 3 (employee self-rating) are DONE. You are EXTENDING the existing Flutter app, not rebuilding it. Do not modify or break anything in lib/features/auth/, lib/features/hr/, lib/features/employee/, or lib/core/.

═══════════════════════════════════════════════════════════════════
EXISTING APP — DO NOT MODIFY
═══════════════════════════════════════════════════════════════════

Already in place from Steps 1-3:
- flutter_riverpod ^2.4.9, go_router ^13.0.0, dio ^5.4.0
- flutter_secure_storage, shimmer ^3.0.0, connectivity_plus ^5.0.2
- google_fonts (Plus Jakarta Sans), intl ^0.19.0, shared_preferences
- AppColors palette (primaryPurple #6B1F7C, accentOrange #FF6B1A, accentYellow #FFB800, accentRed #E63946)
- ApiError + ApiErrorType + AuthException + AsyncValueView + PagedListView + AppRoutes
- Existing shared widgets: ConfirmActionDialog, EmptyState, ErrorState, CurrencyText, DateText, RelativeTimeText, DecimalField, ShimmerBox, ListItemSkeleton, DashboardCardSkeleton, KraTableSkeleton, ProfileHeaderSkeleton, FullScreenLoadingSkeleton, OfflineBanner, ConnectivityWrapper
- UserRole enum (extend with any missing roles; values used: MANAGER, HR_ADMIN, ADMIN, BD_MANAGER, WAREHOUSE_MGR)
- Employee module's shared widgets where reusable: KraScoreInputCard, ScoreSlider, WeightageProgressBar, ScorePill, ReviewStateBadge
- ReviewState enum from Step 3: DRAFT, IN_PROGRESS, EMPLOYEE_SUBMITTED_ALL, MANAGER_RATED_ALL, FINALIZED, ACKNOWLEDGED (extend if needed)

The placeholder manager dashboard at /manager currently exists from Step 1. Replace it with the full Manager shell.

═══════════════════════════════════════════════════════════════════
NAVIGATION ARCHITECTURE — TWO MODES IN ONE SHELL
═══════════════════════════════════════════════════════════════════

A manager has TWO contexts in the app:
1. "My Team" — manage subordinates (Section A endpoints)
2. "My Review" — self-rate own performance (Section D from spec, hits /employee/* endpoints)

The implementation:
- A single ManagerShellScreen with a top-level segmented control switching between MyTeamMode and MyReviewMode
- Each mode has its own StatefulShellRoute.indexedStack with its own bottom nav
- "My Team" bottom nav (4 tabs): Dashboard, Team, History, Profile
- "My Review" bottom nav (4 tabs): Home, Self-Rate, History, Profile
- Active mode pill highlighted in primaryPurple (Team) or accentOrange (Review)
- Active bottom-nav indicator color matches the current mode
- Each mode pill shows a notification badge when pending work exists in the OTHER mode (so user is nudged to switch when needed)

The "My Review" mode in the manager shell REUSES the employee module's screens (EmployeeHomeScreen, SelfRateScreen, MyReviewsHistoryScreen, MyProfileScreen) — do NOT duplicate them. Just wire them into the manager shell's route tree under a different path prefix.

═══════════════════════════════════════════════════════════════════
ROLE-BASED ACCESS
═══════════════════════════════════════════════════════════════════

The /manager/* tree is accessible to users with role: MANAGER, HR_ADMIN, ADMIN, BD_MANAGER, WAREHOUSE_MGR (anyone who might have direct reports).

For HR_ADMIN: after login, default route is /hr/home (their primary work). They can deep-link to /manager/team to access manager flows for escalations. Show a "Switch to Manager view" item in the HR drawer.

For everyone else with manager role: default route after login is /manager/team/dashboard (My Team mode).

If a user has NO direct reports (backend returns 403 NO_DIRECT_REPORTS on /manager/dashboard), gracefully fall back: show a friendly "You don't manage any team members right now" screen with a CTA to go to "My Review" instead.

═══════════════════════════════════════════════════════════════════
BACKEND API CONTRACT (USE EXACTLY)
═══════════════════════════════════════════════════════════════════

Base URL: same as Steps 1-3. All envelopes { success, data, meta? } or { success, error: { code, message } }. Auth: Authorization: Bearer <accessToken>. Decimals as strings ("75.00"). Dates as ISO 8601.

──────── Section A: Manager-specific endpoints ────────

1. GET /api/v1/kra/manager/dashboard
   Returns manager card + active cycle + stats + pendingActions + last-cycle trend

2. GET /api/v1/kra/manager/team?cycleId=&page=&limit=&search=&filterState=
   filterState options: PENDING_MY_REVIEW | COMPLETED | NOT_SUBMITTED | OVERDUE
   Returns paginated list of direct reports with their current-cycle review

3. GET /api/v1/kra/manager/team/:employeeId
   Single employee profile + FY review summary

4. GET /api/v1/kra/manager/reviews/:reviewId
   Full quarterly review with rows[].monthlyScores[]
   Returns: { id, state, isLocked, employee, cycle, rows[{assignmentItemId, name, category, weightage, maxScore, scoreSource, monthlyScores[{monthlyScoreId, monthId, monthLabel, monthStatus, selfRating, selfRemark, managerRating, managerRemark, weightedScore}]}], totals, previousReviews[], managerComment, permissions{canRate, canEdit, deadlineRemaining} }

5. POST /api/v1/kra/manager/reviews/:reviewId/manager-rate
   Body: { scores: [{ monthlyScoreId, managerRating, managerRemark }], managerComment?, autoSubmit }
   Response: { state, totals, transitioned: bool, transitionError: {code, message} | null }
   CRITICAL: handle transitioned=false case (scores saved but state didn't progress)

6. PATCH /api/v1/kra/manager/reviews/:reviewId/manager-rate
   Same body, only allowed when state=MANAGER_RATED_ALL and pre-deadline

7. POST /api/v1/kra/manager/reviews/bulk-approve
   Body: { reviewIds: [...], comment? }
   Response: { approvedCount, skippedCount, approved[{reviewId, employeeName, managerTotal}], skipped[{reviewId, employeeName, reason, detail}] }
   Max 50 reviewIds per call. Skipped reasons include: INCOMPLETE_AFTER_COPY, NOT_EMPLOYEE_SUBMITTED, DEADLINE_PASSED

8. GET /api/v1/kra/manager/team/:employeeId/history?cycleId=&page=&limit=
   Paged historical reviews

10. POST /api/v1/kra/manager/reviews/:reviewId/comment
    Body: { comment }
    Sets managerComment only, no score/state change

──────── Section B: Shared review endpoint we'll use ────────

POST /api/v1/kra/reviews/:id/scores
Use for AUTO-SAVE DRAFT during manager-rate. Body must include side: 'MANAGER'. Cell-level partial saves. Does NOT trigger state transition. Use it every 5 seconds while user is editing in the manager-rate form. Then call POST /manager-rate with autoSubmit=true only when user clicks final Submit.

──────── Section C: Shared endpoints (already wired in Step 1) ────────

POST /auth/login, GET /auth/verify, POST /auth/refresh, POST /auth/logout — already done
GET /locations, GET /kra-templates, GET /review-cycles, GET /bonus-slabs — read-only lookups, use when populating dropdowns

──────── Section D: My Review (manager's self-rating) ────────

Reuse Step 3 endpoints:
GET /api/v1/employee/dashboard
GET /api/v1/employee/reviews
POST /api/v1/employee/reviews/:reviewId/self-rate
GET /api/v1/employee/incentive-summary?cycleId=

These are already wired in Step 3 — just reuse the existing repositories and providers.

═══════════════════════════════════════════════════════════════════
NEW FOLDER STRUCTURE
═══════════════════════════════════════════════════════════════════

```
lib/features/manager/
├── data/
│   ├── models/
│   │   ├── manager_dashboard.dart
│   │   ├── manager_stats.dart
│   │   ├── pending_action.dart
│   │   ├── team_member.dart                  # row from /manager/team
│   │   ├── team_member_profile.dart          # from /manager/team/:id
│   │   ├── fy_review_summary.dart            # nested in team_member_profile
│   │   ├── manager_review_detail.dart        # full GET /manager/reviews/:id
│   │   ├── review_row.dart                   # one KRA item row
│   │   ├── monthly_score.dart                # one cell (item × month)
│   │   ├── review_totals.dart
│   │   ├── review_permissions.dart           # {canRate, canEdit, deadlineRemaining}
│   │   ├── previous_review.dart              # for trend display
│   │   ├── manager_rate_request.dart         # POST body
│   │   ├── manager_rate_response.dart        # includes transitioned flag
│   │   ├── transition_error.dart             # nested error info
│   │   ├── bulk_approve_request.dart
│   │   ├── bulk_approve_response.dart
│   │   ├── bulk_approved_item.dart
│   │   ├── bulk_skipped_item.dart
│   │   ├── manager_team_filter.dart          # enum: PENDING_MY_REVIEW | COMPLETED | NOT_SUBMITTED | OVERDUE
│   │   └── enums.dart                        # extend ReviewState if needed
│   │
│   └── repositories/
│       ├── manager_dashboard_repository.dart        (interface)
│       ├── api_manager_dashboard_repository.dart
│       ├── mock_manager_dashboard_repository.dart
│       ├── manager_team_repository.dart
│       ├── api_manager_team_repository.dart
│       ├── mock_manager_team_repository.dart
│       ├── manager_review_repository.dart
│       ├── api_manager_review_repository.dart
│       ├── mock_manager_review_repository.dart
│       ├── manager_rate_repository.dart
│       ├── api_manager_rate_repository.dart
│       ├── mock_manager_rate_repository.dart
│       ├── bulk_approve_repository.dart
│       ├── api_bulk_approve_repository.dart
│       ├── mock_bulk_approve_repository.dart
│       ├── team_history_repository.dart
│       ├── api_team_history_repository.dart
│       └── mock_team_history_repository.dart
│
└── presentation/
    ├── providers/
    │   ├── manager_dashboard_providers.dart
    │   ├── manager_team_providers.dart
    │   ├── manager_review_providers.dart
    │   ├── manager_rate_providers.dart
    │   ├── bulk_approve_providers.dart
    │   ├── team_history_providers.dart
    │   └── manager_mode_provider.dart        # the segmented switcher state (MyTeam | MyReview)
    │
    ├── screens/
    │   ├── manager_shell_screen.dart         # outer shell with mode switcher + AppBar
    │   │
    │   # MY TEAM MODE
    │   ├── my_team/
    │   │   ├── my_team_shell.dart            # StatefulShellRoute for the 4 manager tabs
    │   │   │
    │   │   ├── dashboard/
    │   │   │   ├── manager_dashboard_screen.dart
    │   │   │   ├── widgets/
    │   │   │   │   ├── manager_greeting_card.dart
    │   │   │   │   ├── manager_stats_grid.dart       # 4 cards: total reports, pending, completed, overdue
    │   │   │   │   ├── pending_actions_list.dart
    │   │   │   │   ├── pending_action_tile.dart
    │   │   │   │   ├── team_trend_card.dart           # last cycle summary
    │   │   │   │   └── no_reports_empty_state.dart
    │   │   │
    │   │   ├── team/
    │   │   │   ├── team_list_screen.dart
    │   │   │   ├── team_member_profile_screen.dart
    │   │   │   ├── widgets/
    │   │   │   │   ├── team_member_tile.dart
    │   │   │   │   ├── team_filter_chips.dart          # 4 filter states
    │   │   │   │   ├── review_state_indicator.dart     # color + label per state
    │   │   │   │   ├── three_month_trend_strip.dart
    │   │   │   │   ├── bulk_select_app_bar.dart        # changes when in select mode
    │   │   │   │   └── bulk_approve_fab.dart           # appears in select mode
    │   │   │
    │   │   ├── review/
    │   │   │   ├── review_detail_screen.dart           # quarterly review view (entry point)
    │   │   │   ├── manager_rate_screen.dart            # the editing matrix
    │   │   │   ├── manager_rate_review_screen.dart     # pre-submit summary
    │   │   │   ├── manager_rate_success_screen.dart    # post-submit (autoSubmit=true)
    │   │   │   ├── manager_rate_partial_success_screen.dart  # transitioned=false handling
    │   │   │   ├── review_readonly_screen.dart         # for FINALIZED/ACKNOWLEDGED reviews
    │   │   │   ├── widgets/
    │   │   │   │   ├── quarterly_review_matrix.dart    # the big grid widget
    │   │   │   │   ├── matrix_view_responsive.dart     # picks accordion vs table by screen size
    │   │   │   │   ├── matrix_table_view.dart          # for tablet+
    │   │   │   │   ├── matrix_accordion_view.dart      # for phone — one item expanded at a time
    │   │   │   │   ├── score_cell.dart                 # individual (item × month) input
    │   │   │   │   ├── readonly_score_cell.dart        # for LOCKED months / non-MANAGER cells
    │   │   │   │   ├── self_rating_chip.dart           # "Self: 8.5" shown below manager input
    │   │   │   │   ├── month_column_header.dart        # sticky monthly total at top
    │   │   │   │   ├── manager_total_footer.dart       # sticky bottom: weighted total
    │   │   │   │   ├── manager_comment_field.dart      # the top-level managerComment textarea
    │   │   │   │   ├── previous_reviews_strip.dart     # last 2 finalised for context
    │   │   │   │   ├── permissions_banner.dart         # explains why edit is disabled
    │   │   │   │   ├── deadline_warning_card.dart      # if deadline ≤ 3 days
    │   │   │   │   └── auto_save_indicator.dart        # subtle "saved 3s ago" text
    │   │   │
    │   │   ├── bulk_approve/
    │   │   │   ├── bulk_approve_confirm_screen.dart
    │   │   │   ├── bulk_approve_result_screen.dart
    │   │   │   └── widgets/
    │   │   │       ├── approved_list_section.dart
    │   │   │       ├── skipped_list_section.dart
    │   │   │       └── skipped_reason_explainer.dart   # maps INCOMPLETE_AFTER_COPY etc. to plain English
    │   │   │
    │   │   ├── history/
    │   │   │   ├── manager_history_screen.dart         # combined history across all team members
    │   │   │   ├── team_member_history_screen.dart     # filtered to one person
    │   │   │   └── widgets/
    │   │   │       └── history_review_tile.dart
    │   │   │
    │   │   └── profile/
    │   │       └── manager_profile_screen.dart         # mirrors employee profile + reporting tree
    │   │
    │   # MY REVIEW MODE (reuse employee screens)
    │   └── my_review/
    │       ├── my_review_shell.dart                    # routes to existing employee screens
    │       └── README.md                               # document: "this mode reuses lib/features/employee/"
    │
    └── widgets/
        ├── mode_segmented_switcher.dart                # the My Team / My Review toggle
        ├── mode_badge.dart                             # notification dot on inactive mode
        ├── manager_app_bar.dart                        # AppBar with switcher slot below
        ├── transitioned_false_alert.dart               # reusable alert for partial-success state
        └── transition_error_message_mapper.dart        # maps backend error codes to user-friendly text
```

═══════════════════════════════════════════════════════════════════
ROUTING — UPDATE app_router.dart
═══════════════════════════════════════════════════════════════════

Use nested StatefulShellRoute. Outer shell holds the mode switcher; inner shells hold each mode's tabs:

```
/manager (ManagerShellScreen — mode switcher in AppBar)
│
├── My Team mode → /manager/team/* (MyTeamShell)
│   ├── /manager/team/dashboard → ManagerDashboardScreen
│   ├── /manager/team/list → TeamListScreen
│   │   ├── /manager/team/:employeeId → TeamMemberProfileScreen
│   │   ├── /manager/team/:employeeId/history → TeamMemberHistoryScreen
│   │   ├── /manager/team/reviews/:reviewId → ReviewDetailScreen
│   │   │   ├── /manager/team/reviews/:reviewId/rate → ManagerRateScreen
│   │   │   ├── /manager/team/reviews/:reviewId/rate/review → ManagerRateReviewScreen
│   │   │   ├── /manager/team/reviews/:reviewId/rate/success → ManagerRateSuccessScreen
│   │   │   └── /manager/team/reviews/:reviewId/rate/partial → ManagerRatePartialSuccessScreen
│   │   ├── /manager/team/bulk-approve → BulkApproveConfirmScreen
│   │   └── /manager/team/bulk-approve/result → BulkApproveResultScreen
│   ├── /manager/team/history → ManagerHistoryScreen (combined)
│   └── /manager/team/profile → ManagerProfileScreen
│
└── My Review mode → /manager/review/* (MyReviewShell — reuses employee screens)
    ├── /manager/review/home → EmployeeHomeScreen (existing)
    ├── /manager/review/self-rate → SelfRateScreen (existing)
    ├── /manager/review/history → MyReviewsHistoryScreen (existing)
    └── /manager/review/profile → MyProfileScreen (existing)
```

Mode switching MUST preserve the user's position in each mode. If a user navigates deep into My Team (e.g., on the rate screen), switches to My Review, then comes back — they should land back on the rate screen, not the team list. Use IndexedStack at the mode level to keep both subtrees alive.

Role guard: only users with role MANAGER, HR_ADMIN, ADMIN, BD_MANAGER, WAREHOUSE_MGR can access /manager/*. Others redirect to /employee/home.

Post-login redirect updates:
- MANAGER, BD_MANAGER, WAREHOUSE_MGR → /manager/team/dashboard
- HR_ADMIN → /hr/home (existing); they can deep-link to manager via drawer
- All other roles → /employee/home (existing)

═══════════════════════════════════════════════════════════════════
MODE SWITCHER — DETAILED SPEC
═══════════════════════════════════════════════════════════════════

`ModeSegmentedSwitcher` widget sits directly below the AppBar (NOT in the AppBar — it's its own row).

Specifications:
- Two pill buttons, equal width, full-width row with 16px horizontal margin
- Active pill: solid brand color (purple for Team, orange for Review), white text, weight 700
- Inactive pill: transparent bg, border 1.5px in divider color, textSecondary text, weight 500
- Animated transition (200ms ease) when switching
- Tap on inactive pill switches mode immediately
- Small notification badge (red dot or count) on inactive pill when work is pending in that mode
  - For "My Review" badge: shown when manager's own review has selfRatingDaysRemaining ≤ 3 OR state=DRAFT/IN_PROGRESS
  - For "My Team" badge: shown when stats.pendingMyReview > 0 OR stats.overdueReviews > 0

Underneath the switcher, the rest of the screen rebuilds based on selected mode (which is held in `managerModeProvider`).

The bottom-nav also adapts to mode: tabs and active color change.

═══════════════════════════════════════════════════════════════════
MANAGER DASHBOARD — DETAILED SPEC
═══════════════════════════════════════════════════════════════════

Layout (top to bottom, scrollable, pull-to-refresh):

1. **Greeting header** (no card)
   - "Good morning, Amol" (time-aware)
   - Subtitle: today's date + employee code chip + role pill

2. **Manager stats grid** — 2x2 on phone, 1x4 on tablet
   - Card 1: Total Reports (number, icon: groups, color: primaryPurple)
   - Card 2: Pending My Review (number, icon: rate_review, color: accentOrange, highlight if > 0)
   - Card 3: Completed This Month (number, icon: check_circle, color: success green)
   - Card 4: Overdue (number, icon: warning, color: accentRed, highlight if > 0)
   - Each card tappable — navigates to team list with that filter pre-applied

3. **Active cycle card** — same component pattern as HR module but manager-focused
   - Cycle name + status badge
   - Manager review deadline date + days remaining (color-coded)
   - Tap → reads more in cycle detail (use shared review cycle screen from HR if possible, read-only mode)

4. **Pending actions list**
   - Section header: "Awaiting your review (N)"
   - Each PendingActionTile shows:
     - Employee avatar + name + employee code chip
     - Month label + "submitted X days ago"
     - Deadline chip (color-coded by daysRemaining)
     - Trailing chevron
   - Tap → navigate to review detail
   - Empty state: "All caught up! 🎉" if list is empty
   - Show max 5; "View all (N)" link below if more

5. **Team trend card** — last completed cycle summary
   - Section: "Last cycle highlights"
   - Average team score
   - Highest performer (name + score)
   - Lowest performer (name + score)
   - Completion rate
   - Tap → opens full team history (defer detailed analytics to Step 7)

All sections:
- Independent shimmer skeletons during load
- Independent error retry buttons
- Wrap in AsyncValueView

═══════════════════════════════════════════════════════════════════
TEAM LIST SCREEN — DETAILED SPEC
═══════════════════════════════════════════════════════════════════

AppBar: "My Team" title, search icon, multi-select toggle icon (for bulk approve)

Below AppBar:
- Search bar (BrandedTextField, 300ms debounce)
- Filter chips horizontal row: All | Pending My Review | Completed | Not Submitted | Overdue
  - Active chip highlighted in primaryPurple
  - Each chip shows count badge: "Pending My Review (3)"

Body:
- PagedListView<TeamMember>
- Each TeamMemberTile:
  - Leading: avatar (initials, colored circle)
  - Title: employee name (16px bold)
  - Subtitle: employeeCode chip + role pill + projectLocation small text
  - Trailing: ReviewStateIndicator
    - State badge with color coding:
      - DRAFT/NOT_SUBMITTED → gray "Not Started"
      - IN_PROGRESS → orange "In Progress (Employee)"
      - EMPLOYEE_SUBMITTED_ALL → primaryPurple "Ready for Review" (CTA-styled)
      - MANAGER_RATED_ALL → success green "You Rated"
      - FINALIZED → muted green "Finalized"
      - OVERDUE → accentRed "Overdue"
    - Below badge: selfTotal or managerTotal or finalTotal (whichever is current)
  - Bottom row: ThreeMonthTrendStrip (3 small dots colored by last 3 monthly scores; gray if no data)
- Tap tile → TeamMemberProfileScreen

Multi-select mode (for bulk approve):
- Toggle via AppBar action
- Tiles get checkbox on left
- AppBar changes to BulkSelectAppBar: shows count "3 selected" + Cancel + Approve button
- Only EMPLOYEE_SUBMITTED_ALL tiles are SELECTABLE (others grayed out with tooltip explaining why)
- Tap Approve → navigate to BulkApproveConfirmScreen with selectedIds
- Floating action button NOT shown in select mode

Pull-to-refresh, pagination, search debouncing, empty states for each filter:
- "All": "Your team list is empty. Reach out to HR if this is unexpected."
- "Pending My Review": "No one is waiting for your review right now. 🎉"
- "Completed": "You haven't completed any reviews this cycle yet."
- "Not Submitted": "All your team members have started their reviews."
- "Overdue": "No overdue reviews — great job staying on top of things!"

═══════════════════════════════════════════════════════════════════
TEAM MEMBER PROFILE SCREEN — DETAILED SPEC
═══════════════════════════════════════════════════════════════════

Tabs: Profile | Current Review | History

**Profile tab:**
- ProfileHeader: large avatar + name + role pill + employee code
- Sections (using ProfileFieldRow widget reused from employee profile):
  - Contact: email, phone
  - Org: department, grade, position, project location
  - Joining: joinedDate, monthly incentive amount
- FY Review Summary card:
  - Total reviews this FY
  - Finalized count
  - Pending count
  - Average final score

**Current Review tab:**
- Embedded ReviewDetailScreen content (not a separate route, embedded as tab content)
- Shows the quarterly matrix in read-mode if state != EMPLOYEE_SUBMITTED_ALL
- Shows "Start Rating" CTA if state == EMPLOYEE_SUBMITTED_ALL → navigates to /rate

**History tab:**
- Embedded TeamMemberHistoryScreen content
- Paginated list of past reviews
- Tap any → ReviewReadonlyScreen

═══════════════════════════════════════════════════════════════════
REVIEW DETAIL SCREEN — THE MOST IMPORTANT MANAGER UI
═══════════════════════════════════════════════════════════════════

This is the entry point for rating. Behavior depends on state:

**If state == EMPLOYEE_SUBMITTED_ALL and permissions.canRate == true:**
- Show review summary at top (employee info, cycle, month tabs as the quarter spans 3 months)
- Show the quarterly matrix in READ-ONLY mode with employee self-ratings visible
- Prominent CTA at bottom: "Start Rating" button → navigate to ManagerRateScreen

**If state == IN_PROGRESS (employee still rating):**
- Show banner: "Waiting for [employee name] to complete self-rating"
- Show partial self-ratings (whatever's there)
- CTA disabled, tooltip explains

**If state == MANAGER_RATED_ALL and permissions.canEdit == true:**
- Show full matrix with manager's ratings filled in (read-only)
- Show managerComment if set
- CTA: "Edit My Rating" → ManagerRateScreen (PATCH mode)

**If state == FINALIZED or ACKNOWLEDGED:**
- Show full read-only review
- Display final totals + incentive amount
- No edit affordances

**If state == DRAFT (employee not started):**
- Show empty state: "[Employee] hasn't started self-rating yet"
- No matrix visible
- No CTA

**Always show:**
- Header: employee name + cycle name + month chips (Apr-26, May-26, Jun-26)
- Sticky bottom info: state badge + manager total + deadline remaining
- Previous reviews strip (last 2 finalised quarters as small cards)

═══════════════════════════════════════════════════════════════════
MANAGER-RATE SCREEN — THE EDITING MATRIX
═══════════════════════════════════════════════════════════════════

The most complex screen in the app. Build for both phone and tablet.

**Responsive strategy** (via LayoutBuilder):

PHONE (< 600px wide): Accordion layout
- Each KRA row is a collapsible section
- Header shows: KRA name + weightage + current weighted score
- Expanding shows 3 monthly score cells stacked vertically with their inputs
- One section expanded at a time (auto-collapse others)
- Sticky top: "Weighted Total: X.X / 100" with progress bar

TABLET / WEB (≥ 600px wide): Table layout
- Horizontal scroll if needed
- Rows = KRA items, Columns = months
- Column headers sticky (month labels + monthly totals)
- Last column: weighted score for the item (auto-calculated)
- Bottom sticky row: monthly totals + grand total

**Each ScoreCell shows:**
- Manager rating input (TextField with numeric keyboard, accepts decimals)
  - Validation: 0 ≤ value ≤ maxScore (defaultMaxScore from item)
  - Inline error on invalid
- Below input: "Self: X.X" chip in muted color (shows employee's self-rating for context)
- Tap to expand: optional managerRemark textarea (200 char limit, char counter)
- Visual states:
  - Empty: divider border
  - Filled: success green border
  - Invalid: error red border
  - Read-only (LOCKED month or scoreSource != MANAGER): grayed out, "Locked" or "Auto" badge

**Top of screen:**
- Manager comment textarea (managerCommentField widget)
- Placeholder: "Leave an overall comment for [Employee name]..."
- 500 char limit
- Saves with auto-save

**Bottom sticky bar:**
- Left: live weighted total (e.g. "73.5 / 100")
- Right: "Review" button (primary, full-height)
- Disabled until ALL editable cells have valid scores

**Auto-save behavior:**
- Every 5 seconds while editing (debounced — only fires if there are unsaved changes)
- Use POST /reviews/:id/scores with side: 'MANAGER' for each changed cell
- Show subtle indicator: "Saved 3s ago" near manager comment field
- If auto-save fails: switch indicator to red "Couldn't save — retrying" + manual retry button
- Auto-save does NOT trigger state transition (that's only on final submit)

**Resume draft:**
- If user navigates away and returns, fetch latest review from server (auto-saved state is already on server)
- No local SharedPreferences needed for managers — server is source of truth
- If permissions.canRate becomes false (deadline passed while away): show DeadlinePassedScreen

**Submit flow:**
- "Review" button → ManagerRateReviewScreen (pre-submit summary)
- That screen shows full matrix in read-only summary form + manager comment
- "Edit" and "Submit Final" buttons
- "Submit Final" → confirm dialog "Once submitted, you cannot change scores unless you reopen within deadline. Continue?"
- Confirm → POST /manager-rate with autoSubmit=true
- Loading spinner → response handling (see Submit Response Handling below)

═══════════════════════════════════════════════════════════════════
SUBMIT RESPONSE HANDLING — CRITICAL
═══════════════════════════════════════════════════════════════════

After POST /manager-rate, parse response carefully:

```dart
if (response.transitioned == true) {
  // FULL SUCCESS
  // Navigate to ManagerRateSuccessScreen
  // Show: "Review submitted ✓"
  // CTA: "View submission" or "Back to team"
}

if (response.transitioned == false) {
  // PARTIAL SUCCESS (scores saved but state didn't move)
  // Navigate to ManagerRatePartialSuccessScreen
  // Show:
  //   - Yellow/orange alert icon
  //   - "Scores saved successfully"
  //   - "Review can't be finalized yet:"
  //   - response.transitionError.message in human-friendly form
  //   - List of what's missing (e.g., "Ops feed missing for Customer Escalations")
  // CTAs:
  //   - "Try Submit Again" (re-fires POST /manager-rate)
  //   - "Back to Review" (returns to detail view)
  // The review state badge in lists still shows IN_PROGRESS
}

if (error) {
  // FAILURE
  // Stay on rate screen
  // Show error snackbar with retry
  // Local data preserved (auto-saved already)
}
```

Build a `TransitionErrorMessageMapper` utility that maps backend error codes to user-friendly messages:
- INCOMPLETE_AFTER_COPY → "Ops or Finance hasn't filled in some scores yet"
- MONTH_LOCKED → "One of the months in this review is locked"
- DEADLINE_PASSED → "Review deadline has passed"
- (catch-all) → use the message from transitionError.message

═══════════════════════════════════════════════════════════════════
BULK APPROVE FLOW
═══════════════════════════════════════════════════════════════════

**Entry:** Team list → toggle multi-select → tap Approve → BulkApproveConfirmScreen

**BulkApproveConfirmScreen:**
- Title: "Approve X reviews?"
- List of selected employees with their selfTotals
- Optional manager comment field (applied to all)
- Warning text: "This copies the employee's self-ratings as your ratings for items you score (MANAGER source). Items scored by Ops/Finance are not affected."
- Bottom buttons: Cancel + "Confirm & Approve"
- Confirm → POST /bulk-approve → loading → BulkApproveResultScreen

**BulkApproveResultScreen:**
- Top: summary banner (success green if all approved, accentOrange if some skipped)
- "Approved: X" section
  - List of ApprovedListSection items (employee name + new managerTotal)
- "Skipped: Y" section (only if any skipped)
  - Each SkippedItem shows: employee name + plain-English reason
  - Tap to expand → see detail (the technical reason from backend)
  - Use SkippedReasonExplainer to map codes:
    - INCOMPLETE_AFTER_COPY → "Ops or Finance hasn't filled in their scores yet — you'll need to wait or rate manually"
    - NOT_EMPLOYEE_SUBMITTED → "Employee hasn't finished their self-rating"
    - DEADLINE_PASSED → "Review deadline has passed"
- CTA: "Done" → back to team list

═══════════════════════════════════════════════════════════════════
TEAM HISTORY SCREENS
═══════════════════════════════════════════════════════════════════

Two variants:

**ManagerHistoryScreen** (accessed from My Team mode → History tab)
- Combined view across all team members
- Filters: cycle dropdown, employee dropdown
- Paginated list of past reviews from ALL direct reports
- Each tile: employee + month/cycle + state badge + final score (if finalized)
- Tap → ReviewReadonlyScreen

**TeamMemberHistoryScreen** (accessed from team member profile)
- Filtered to one employee
- Same tile UI as above

═══════════════════════════════════════════════════════════════════
MY REVIEW MODE — REUSE EMPLOYEE SCREENS
═══════════════════════════════════════════════════════════════════

In `my_review/my_review_shell.dart`, wire the existing employee screens:
- /manager/review/home → EmployeeHomeScreen (lib/features/employee/presentation/screens/home/employee_home_screen.dart)
- /manager/review/self-rate → SelfRateScreen
- /manager/review/history → MyReviewsHistoryScreen
- /manager/review/profile → MyProfileScreen

The screens themselves DO NOT NEED MODIFICATION. They already handle the manager's-own-review case because they're authenticated by token; the backend serves the right data automatically.

Just create thin route wrappers in the manager module. Add a README.md in `my_review/` explaining the reuse so future devs don't recreate these screens.

═══════════════════════════════════════════════════════════════════
PRODUCTION STANDARDS — APPLY ALL (SAME BAR AS STEPS 1-3)
═══════════════════════════════════════════════════════════════════

1. ✅ All API endpoints from Section A wired through Dio repos with proper error mapping
2. ✅ Repository pattern: interface + Mock impl + Api impl for every repo
3. ✅ Default to Mock during development (one-line swap to Api)
4. ✅ Riverpod AsyncNotifier pattern, autoDispose where appropriate
5. ✅ Shimmer skeletons on EVERY loading state (no spinners on main loads)
6. ✅ Pull-to-refresh on all lists and the dashboard
7. ✅ Pagination on team list, history list, bulk approve result list
8. ✅ Search debouncing (300ms) on team search
9. ✅ Optimistic UI on bulk approve (immediate badge update on success)
10. ✅ Auto-save on manager-rate (5s debounce via POST /reviews/:id/scores)
11. ✅ All errors mapped to user-friendly Indian English (no DioException leaks)
12. ✅ The transitioned=false case handled DISTINCTLY from full success
13. ✅ Bulk approve skipped reasons mapped via SkippedReasonExplainer
14. ✅ Indian currency formatting (₹1,37,835.00)
15. ✅ Indian date formatting ("12 May 2026")
16. ✅ Decimal-as-string round-trip preserved
17. ✅ Connectivity awareness: mutations disabled when offline
18. ✅ Confirm dialogs on all destructive/irreversible actions
19. ✅ Empty states for every list with friendly copy + CTA
20. ✅ Error states with retry buttons
21. ✅ All AsyncValue cases handled via AsyncValueView
22. ✅ All strings in app_strings.dart (extend with new section: // ─── Manager Module ───)
23. ✅ All colors via AppColors only
24. ✅ go_router named routes only (extend AppRoutes class)
25. ✅ Role guard for /manager/* enforced in router redirect logic
26. ✅ Mode switcher preserves position in each mode via IndexedStack
27. ✅ Notification badges on inactive mode pill
28. ✅ Read-only states (FINALIZED, LOCKED months, non-MANAGER cells) render distinctly
29. ✅ Permissions object from API drives UI affordances (canRate, canEdit, deadlineRemaining)
30. ✅ HR_ADMIN drawer item: "Switch to Manager view"

═══════════════════════════════════════════════════════════════════
HARD REQUIREMENTS RECAP
═══════════════════════════════════════════════════════════════════

1. ✅ 7 repository interfaces + 7 Api impls + 7 Mock impls (21 files)
2. ✅ ~22 model classes with full fromJson/toJson/copyWith
3. ✅ 7 Riverpod provider files + 1 mode provider
4. ✅ ManagerShellScreen with mode switcher
5. ✅ MyTeamShell with 4 tabs (Dashboard, Team, History, Profile)
6. ✅ MyReviewShell with 4 tabs reusing employee screens
7. ✅ Manager dashboard with greeting + stats grid + active cycle + pending actions + team trend
8. ✅ Team list with filters + search + pagination + multi-select + bulk approve entry
9. ✅ Team member profile with 3 tabs (Profile, Current Review, History)
10. ✅ Review detail with state-dependent UI
11. ✅ Manager-rate screen with responsive matrix (accordion phone, table tablet+)
12. ✅ Auto-save via POST /reviews/:id/scores every 5s
13. ✅ Submit response handling: full success, partial success (transitioned=false), failure
14. ✅ Bulk approve confirm + result screens with approved/skipped split
15. ✅ History (combined + per-employee)
16. ✅ Readonly review screen for FINALIZED states
17. ✅ All edge cases: LOCKED months, non-MANAGER cells, deadline passed, no direct reports
18. ✅ Updated app_router.dart with full /manager/* nested routes
19. ✅ Updated app_strings.dart with new section
20. ✅ Updated post-login redirect logic

═══════════════════════════════════════════════════════════════════
OUTPUT FORMAT
═══════════════════════════════════════════════════════════════════

Generate every file in full. No diffs, no placeholders, no "// rest unchanged". After all code, provide:

1. **Updated pubspec.yaml** — flag any new deps needed (likely none beyond Steps 1-3)
2. **Updated app_strings.dart** with all new Manager strings appended under `// ─── Manager Module ───` section
3. **Updated app_router.dart** with the full /manager/* nested routes via StatefulShellRoute and updated post-login redirect logic
4. **Updated UserRole enum** if any roles need adding

5. **A comprehensive test checklist** covering:
   - Login as manager@vistar.test → lands on /manager/team/dashboard
   - Dashboard loads with shimmer then 5 reports + 1 pending (Vikram)
   - Tap pending action card → navigates to Vikram's review detail
   - Review detail shows "Start Rating" CTA (state=EMPLOYEE_SUBMITTED_ALL)
   - Tap CTA → manager-rate screen opens with full matrix
   - On phone: accordion layout; on tablet: table layout
   - Each cell shows "Self: X.X" chip below input
   - Enter scores → weighted total updates live
   - LOCKED months render read-only
   - Auto-save fires every 5s → "Saved 3s ago" indicator
   - Navigate away, return → all scores still there (server persisted)
   - Try score = 15 (out of 10 max) → inline validation error
   - Fill all cells → tap Review → pre-submit summary screen
   - Tap Submit Final → confirm dialog → POST /manager-rate
   - If transitioned=true → success screen → back to team list, Vikram's badge updates to "You Rated"
   - If transitioned=false → partial success screen with clear "what's missing" message
   - Team list multi-select: select 2 EMPLOYEE_SUBMITTED_ALL employees → Approve → confirm → result screen
   - Approved count + skipped count shown distinctly
   - Skipped employee's reason mapped to plain English
   - Filter chips work: PENDING_MY_REVIEW shows only Vikram, COMPLETED shows Sagar etc.
   - Search debounces 300ms
   - Pagination triggers on scroll
   - Sagar (MANAGER_RATED_ALL) → tap Edit → matrix becomes editable → PATCH works
   - Neha (FINALIZED) → read-only view with incentive amount + history tab
   - Pravin (IN_PROGRESS) → "Waiting for employee" banner
   - Anita (DRAFT) → "Hasn't started" empty state
   - Switch to "My Review" mode → bottom nav swaps → lands on employee home (manager's own review)
   - Notification badge on "My Team" pill while in My Review mode if pending review exists
   - Lose internet → offline banner → mutations disabled → reads serve cached data
   - HR_ADMIN drawer: "Switch to Manager view" → lands on /manager/team/dashboard
   - Logout → /login → can't back-navigate to /manager/*

6. **A short note on what Step 5 (Ops module) will need from this** — specifically, the Ops dashboard will mirror this manager dashboard pattern but score `scoreSource=OPS` cells across all reviews in their region.

DO NOT abbreviate. DO NOT skip files. Output must be production-ready and runnable with `flutter pub get && flutter run` immediately after pasting into the project. Default repositories to Mock so the app runs without backend dependency; provide a clear note explaining how to swap to Api (single line change per provider).