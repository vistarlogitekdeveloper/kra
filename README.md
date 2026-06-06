# Vistar KRA & Incentive Management

The company-wide app for setting goals, reviewing performance, and paying out incentive that follows. Every Vistar employee uses it; the surface they see depends on their role.

Built with Flutter (Android, iOS, Web, Desktop).

## Quick start

```bash
flutter pub get
flutter analyze        # must report "No issues found"
flutter test           # must end with "All tests passed!"
flutter run            # launches on the connected device
```

Drop the Vistar logo at `assets/images/vistar_logo.png` if it isn't already there.

## Live test credentials

All passwords are `Vistar@123`. The backend lives at `https://vistar-crm.onrender.com/api/v1/kra/`.

| Role     | Email                    | Review state for testing               |
| -------- | ------------------------ | -------------------------------------- |
| HR_ADMIN | `hr.admin@vistar.test`   |                                        |
| MANAGER  | `manager@vistar.test`    | manages emp1–emp3                      |
| EMPLOYEE | `emp1@vistar.test`       | DRAFT (use this to exercise self-rate) |
| EMPLOYEE | `emp2@vistar.test`       | EMPLOYEE_SUBMITTED_ALL                 |
| EMPLOYEE | `emp3@vistar.test`       | FINALIZED                              |

> **Render cold-start:** the first request after ~15 minutes of inactivity can take 30–60 s. Wait it out before filing a "loading forever" bug.

## Architecture

Feature-first clean architecture. Each module follows `data/{models,repositories}` + `presentation/{providers,screens,widgets}`.

```
lib/
├── core/                shared infra (api, router, theme, widgets, constants, storage)
└── features/
    ├── auth/            login + token lifecycle (live API)
    ├── hr/              HR Admin module (live API)
    ├── manager/         Manager surface (live API)
    └── employee/        Employee surface (live API)
```

All four modules talk to the live backend.

## Roles → home screens

The router picks the landing screen from the authenticated user's role; deep-links to other roles' areas are bounced.

| Role                                    | Lands at                       |
| --------------------------------------- | ------------------------------ |
| `HR_ADMIN`, `HR`, `ADMIN`               | `/hr/home`                     |
| `MANAGER`, `BD_MANAGER`, `WAREHOUSE_MGR`| `/manager/team/dashboard`      |
| `EMPLOYEE`, `OPS`, `FINANCE`            | `/employee/home`               |

`/employee/*` is intentionally shared across roles — managers and HR_ADMIN self-rate through it.

## Where to read next

- **[USER_MANUAL.md](USER_MANUAL.md)** — what each screen does and how a quarter flows end-to-end (setup → self-rate → manager-rate → finalise → payout).
- **[TESTING_GUIDE.md](TESTING_GUIDE.md)** — step-by-step manual test plan with stable case IDs (e.g. *3.5*), credentials, severity rubric, and a known-unbuilt list so testers don't file noise tickets.
- **[CLAUDE.md](CLAUDE.md)** — project guide for AI assistants (stack, conventions, status).
- **[docs/BACKEND_RBAC_FINDINGS.md](docs/BACKEND_RBAC_FINDINGS.md)** — current backend role-enforcement audit results + reproducible Node probe script.

## Optional tooling

```bash
node scripts/probe-rbac.mjs    # probe live backend RBAC; results in docs/BACKEND_RBAC_FINDINGS.md
```

## Status

| Step | Module    | State                                                                                         |
| ---- | --------- | --------------------------------------------------------------------------------------------- |
| 1    | Auth      | ✅ live API                                                                                    |
| 2    | HR Admin  | ✅ live API (audit log aliased to recent-activity; reports/close-cycle still placeholders)     |
| 3    | Employee  | ✅ live API                                                                                    |
| 4    | Manager   | ✅ live API (combined team-history endpoint pending on backend)                                |

See [CLAUDE.md §Project Status](CLAUDE.md#project-status) for the full caveat list.
