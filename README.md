# Vistar App — Step 1: Login & Role-Based Routing


5 test accounts — all use password Vistar@123:

Email	Code	Role	Notes
hr.admin@vistar.test	EMP001	HR_ADMIN	M3 grade
manager@vistar.test	EMP002	MANAGER	M2, manages EMP003-005
emp1@vistar.test	EMP003	EMPLOYEE	E1, review state: DRAFT
emp2@vistar.test	EMP004	EMPLOYEE	E1, review state: EMPLOYEE_SUBMITTED_ALL
emp3@vistar.test	EMP005	EMPLOYEE	M1, review state: FINALIZED
ops@vistar.test	EMP006	OPS_EXCELLENCE	M2
finance@vistar.test	EMP007	FINANCE	

Role	Email
HR_ADMIN	hr.admin@vistarlogitek.com
FINANCE	finance@vistarlogitek.com
OPS_EXCELLENCE	ops@vistarlogitek.com
MANAGER	manager@vistarlogitek.com
EMPLOYEE	employee@vistarlogitek.com



## Setup

```bash
flutter pub get
flutter run
```

Drop the Vistar logo at `assets/images/vistar_logo.png` if it isn't already there.

## Test Accounts (mock backend)

All passwords are `password123`.

| Employee ID | Name | Role |
|---|---|---|
| VLPL0003 | Pravin Wakchware | Employee |
| VLPL0123 | Amol Veer | Manager |
| VLPL0107 | Muralidharan K | Ops Excellence |
| VLPL0610 | Swati Kotkar | HR |
| VLPL0099 | Sagar Sasane | Finance |

You can also log in with email (e.g. `pravin@vistar.com`).

## Folder Structure

```
lib/
├── core/                    Shared infrastructure
│   ├── constants/           Colors, strings, asset paths
│   ├── theme/               Single source of truth for styling
│   └── router/              GoRouter with auth-aware redirects
└── features/
    ├── auth/
    │   ├── data/            Models + repository (mock for now)
    │   └── presentation/    Login screen, providers, widgets
    └── dashboards/          Placeholder dashboards per role
```

## When the Real Backend is Ready

Open `lib/features/auth/presentation/providers/auth_providers.dart`, find
this line:

```dart
return MockAuthRepository();
```

Replace it with `ApiAuthRepository()` (a class you'll write that calls
your real `/api/auth/login` endpoint). The login screen, router, and
state management do not need any other changes.

## What Step 1 Delivers

- Branded login screen (Vistar colors, logo, animations)
- Form validation (empty / too-short fields caught before submit)
- Show/hide password toggle
- Loading state on the button
- Error messages via SnackBar
- Auto-redirect: logged-in users skip login, logged-out users can't reach dashboards
- 5 placeholder dashboards (employee/manager/ops/hr/finance)
- Logout works and returns to login

## Step 2 (Next)

Build the **HR Module** — KRA setup, employee master, bonus slabs.
Without this data nothing else has anything to operate on.
