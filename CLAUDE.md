# Vistar KRA App — Project Guide for Claude

## Stack
- Flutter 3.10+, Dart 3+
- State: flutter_riverpod ^2.4.9 (sealed-class pattern, no setState)
- Routing: go_router ^13.0.0 (named routes only, never raw strings)
- HTTP: dio ^5.4.0 with custom interceptors
- Secure storage: flutter_secure_storage (NEVER shared_preferences for tokens)
- Loading: shimmer ^3.0.0
- Connectivity: connectivity_plus ^5.0.2

## Architecture
Feature-first clean architecture:
```
lib/
├── core/                 (shared infra: api, theme, router, storage, widgets)
├── features/auth/        (Step 1 — DONE, do not modify)
└── features/hr/          (Step 2 — what we're testing)
    ├── data/models/
    ├── data/repositories/
    └── presentation/{providers,screens,widgets}/
```

## Backend
- Base URL: https://api.vistar.com/api/v1 (read from api_constants.dart)
- All envelopes: `{ success, data, meta? }` or `{ success, error: { code, message } }`
- Auth: Bearer token in header
- Decimals come as strings ("7000.00") — parse to double in models
- Dates come as ISO 8601 strings — parse to DateTime
- Lists return `meta: { page, limit, total, totalPages }`

## Brand
- Primary: #6B1F7C (purple)
- Accents: #FF6B1A orange, #FFB800 yellow, #E63946 red
- Font: Plus Jakarta Sans (via google_fonts)
- Currency: Indian format (₹1,37,835.00) via intl
- Dates: "12 May 2026" format

## Key Conventions
- All strings in `core/constants/app_strings.dart`
- All colors in `core/constants/app_colors.dart`
- All routes in `core/router/app_router.dart` AppRoutes class
- Repository interfaces are abstract — never call Dio directly from UI
- Every async screen uses AsyncValueView (loading/data/error)
- Every list uses PagedListView with shimmer at end
- All destructive actions use ConfirmActionDialog (red variant)

## Test Credentials (mock backend)
- HR_ADMIN: VLPL0610 / password123 (Swati Kotkar)

## How to Run
```bash
flutter pub get
flutter analyze        # must be 0 errors
flutter run            # launches on connected device/emulator
flutter test           # runs all tests
```

## Current Status
Step 1: Auth ✅
Step 2: HR Admin Module — verifying now
Step 3: Employee Module — not started

## What I Need You to Do
Read the spec in `STEP2_SPEC.md` (the prompt I used to build this), then verify the implementation against it. Find bugs, fix them, write tests where useful.