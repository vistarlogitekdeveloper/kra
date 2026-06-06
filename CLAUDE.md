# Vistar KRA App — Project Guide for Claude

## Stack
- Flutter 3.10+, Dart 3+
- State: `flutter_riverpod` ^2.4.9 (sealed-class state for auth; `StateNotifierProvider` + `FutureProvider` elsewhere; no `setState` for cross-screen state)
- Routing: `go_router` ^13.0.0 (constants on `AppRoutes`, never raw strings at call sites)
- HTTP: `dio` ^5.4.0 with `AuthInterceptor` + `RefreshInterceptor` + `ApiLoggerInterceptor`
- Secure storage: `flutter_secure_storage` (NEVER `shared_preferences` for tokens)
- Loading: `shimmer` ^3.0.0
- Connectivity: `connectivity_plus` ^5.0.2

## Architecture
Feature-first clean architecture. All four feature modules are on the live API:
```
lib/
├── core/                 (api, theme, router, storage, widgets, constants)
└── features/
    ├── auth/             (login + token lifecycle)
    ├── hr/               (HR Admin: employees, templates, cycles, slabs, locations, reports, audit log)
    ├── manager/          (My Team: dashboard, team, history, rate matrix, bulk approve)
    └── employee/         (home, self-rate, history, profile)
```

Each module follows `data/{models,repositories}` + `presentation/{providers,screens,widgets}`. Repositories expose an abstract contract; UI binds to the contract, never to Dio directly. The provider layer caches with `ref.keepAlive()` where appropriate to avoid refetching on scroll.

## Backend
- Base URL: `https://vistar-crm.onrender.com/api/v1/kra/` (see `lib/core/api/api_constants.dart`). All three "env" labels currently alias to the same Render-hosted test backend.
- Envelopes: `{ success: true, data: ..., meta?: { page, limit, total, totalPages } }` or `{ success: false, error: { code, message } }`. Parsers live in `core/api/envelope.dart` (`unwrapObject`, `unwrapList`, `unwrapPaged`, `unwrapMeta`).
- Auth: Bearer token on every request except `noAuthEndpoints` (login, refresh). 401 → `RefreshInterceptor` refreshes once and retries (mutex-guarded); on `TOKEN_INVALID` / `REFRESH_TOKEN_REUSE` or refresh failure, forced-logout fires.
- Decimals come as strings (e.g. `"7000.00"`) — `JsonParse.parseDouble` handles both string and number forms.
- Dates come as ISO 8601 — `JsonParse.parseDate` returns `DateTime?`.
- Live payloads sometimes nest fields under `employee.*` / `reviewCycle.*` where the early spec was flat; models use a dual-read pattern (live name first, flat fallback) — see `team_member.dart`, `manager_review_detail.dart`, `pending_action.dart`, `previous_review.dart`.

## Brand
- Primary: `#6B1F7C` (purple)
- Accents: `#FF6B1A` orange, `#FFB800` yellow, `#E63946` red
- Font: Plus Jakarta Sans (via `google_fonts`)
- Currency: Indian format (`₹1,37,835.00`) via `intl`
- Dates: `"12 May 2026"` (`d MMM yyyy`)

## Key Conventions
- All user-facing strings in `core/constants/app_strings.dart`
- All colors in `core/constants/app_colors.dart`
- All routes in `core/router/app_router.dart` under `AppRoutes`
- Repository interfaces are abstract; UI binds to the contract
- Every async screen has shimmer + error-with-retry + empty-state branches
- Every paginated list uses `PagedListView` (pull-to-refresh + shimmer-at-end)
- All destructive actions use `ConfirmActionDialog` (red variant)

## Live Test Credentials
All passwords are `Vistar@123`.

| Role     | Email                    | Notes                                      |
| -------- | ------------------------ | ------------------------------------------ |
| HR_ADMIN | `hr.admin@vistar.test`   | (note the dot)                             |
| MANAGER  | `manager@vistar.test`    | manages emp1–emp3                          |
| EMPLOYEE | `emp1@vistar.test`       | E1 grade, review state DRAFT               |
| EMPLOYEE | `emp2@vistar.test`       | E1 grade, review state EMPLOYEE_SUBMITTED_ALL |
| EMPLOYEE | `emp3@vistar.test`       | M1 grade, review state FINALIZED           |

> The historical `VLPL0610 / password123` accounts only existed in the mock auth repository, which has been deleted. Only the `@vistar.test` accounts above work today.

## Render cold-start
The backend is hosted on Render's free tier. The first request after ~15 minutes of inactivity can take 30–60 s. Subsequent requests are fast. Don't file a "loading forever" bug without waiting it out first.

## How to Run
```bash
flutter pub get
flutter analyze        # must be 0 errors
flutter test           # must end with "All tests passed!"
flutter run            # launches on connected device/emulator
```

## Optional: live backend RBAC probe
`scripts/probe-rbac.mjs` logs in with each available test account and probes HR / Manager / Shared endpoints, printing 200 / 403 / LEAK per cell. Re-run after backend changes; see `docs/BACKEND_RBAC_FINDINGS.md` for the latest results.

```bash
node scripts/probe-rbac.mjs
```

## Project Status
- Step 1 — Auth: ✅ live API
- Step 2 — HR Admin: ✅ live API (audit log routed via `/hr/dashboard/recent-activity` until backend ships `/audit-logs`; close-cycle / reports / bulk-setup are still placeholders)
- Step 3 — Employee: ✅ live API
- Step 4 — Manager: ✅ live API (combined team-history endpoint isn't on the backend yet; the screen guides users to per-employee history which works)

## Where to read next
- [USER_MANUAL.md](USER_MANUAL.md) — what each screen does, role-by-role.
- [TESTING_GUIDE.md](TESTING_GUIDE.md) — step-by-step manual test plan with stable case IDs.
- [docs/BACKEND_RBAC_FINDINGS.md](docs/BACKEND_RBAC_FINDINGS.md) — backend role-enforcement audit + reproducible probe.
