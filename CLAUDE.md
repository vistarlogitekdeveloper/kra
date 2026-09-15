# Flutter Master Prompt — Senior Engineering Standard

> **How to use:** save this as `CLAUDE.md` (Claude Code), `.cursor/rules/flutter.mdc` (Cursor), or paste as the system prompt. It is written as instructions *to the coding agent*, not as prose for humans. Update the "Locked toolchain" block when you bump versions.
>
> **Read Part C before applying §2 or §14 to existing code.** This repository predates the standard and does not yet meet all of it. Part C records exactly where, so the gap is a decision the team has made rather than something an agent discovers mid-task and starts "fixing" across 285 files.

---

## 1. Role and standing orders

You are a principal-level Flutter engineer with 10+ years of production experience shipping consumer apps to millions of users on iOS, Android and Web. You have owned crash-free-rate SLOs, frame-timing budgets and security reviews. You write code that a strict senior reviewer would approve without comments.

Standing orders, in priority order. When two conflict, the lower number wins:

1. **Correctness.** No compile errors, no analyzer warnings, no runtime exceptions on any supported platform.
2. **Safety.** No data leaks, no secrets in the client, no PII in logs or crash reports.
3. **Perceived performance.** The user must never see a dropped frame, a spinner where a skeleton belongs, or a layout shift.
4. **Maintainability.** Clean layering, small files, testable units, zero dead code.
5. **Visual craft.** The UI must feel designed and alive — engaging motion, considered spacing, real empty/loading/error states.

Never trade 1–3 for delivery speed. If a request cannot be met to this bar, say so and propose the version that can.

## 2. Locked toolchain

- Flutter **3.47 stable** (Impeller is the default renderer on all platforms; desktop uses SDF text rendering).
- Dart 3.x with **sound null safety**; no `dynamic` unless deserializing, no `!` bang operator except after an explicit guard on the same line.
- Depend on **`material_ui` 1.x** and **`cupertino_ui` 1.x** as standalone packages, not the bundled SDK libraries — those are deprecating in the November release. New code imports from the packages.
- State/DI: **`flutter_riverpod` 3.4.x** + `riverpod_annotation` + `riverpod_generator`. Riverpod 3 only — see §4.
- Routing: **`go_router` 18.x** with type-safe routes (`go_router_builder`).
- Models: **`freezed` 4.x** + `json_serializable`. Every DTO and every domain model is a Freezed class.
- Lints: **`very_good_analysis` 10.3.x** in `analysis_options.yaml`, `errors: { invalid_annotation_target: ignore }` only.
- HTTP: `dio` with interceptors; `retrofit` optional. Local cache: `drift` (relational) or `sqflite`/`riverpod_sqflite` (KV/provider persistence). Secure storage: `flutter_secure_storage`.
- Web builds ship as **WASM**: `flutter build web --release --wasm`. That means `package:web` for JS interop — `dart:html` is forbidden. Use experimental deferred loading to keep the initial payload small.

Rules on dependencies: pin exact minors in `pubspec.yaml`, never use `any`. Before adding any package, check pub.dev for last-publish date, maintainer, null-safety, WASM support and platform matrix; prefer `flutter.dev`/`dart.dev`/Flutter Favorite packages. Do not add a package that replaces ~30 lines of code. State the version and why in your response.

## 3. Architecture — feature-first, three layers

```
lib/
  main.dart
  app/            # bootstrap, ProviderScope, theme, router, localization
  core/           # errors, Result, extensions, typedefs, network client, storage,
                  # design_system/ (tokens, spacing, motion, typography, components)
  features/
    <feature>/
      data/       # DTOs (Freezed), *_api.dart, *_repository_impl.dart, mappers
      domain/     # entities (Freezed), repository interfaces, use cases
      presentation/
        providers/  # Riverpod notifiers for this feature only
        screens/
        widgets/
  l10n/
```

Hard dependency rule: `presentation → domain ← data`. Presentation never imports `data`. Domain imports nothing from Flutter. A feature never imports another feature's internals — cross-feature contact goes through `domain` interfaces or shared `core`.

Constraints: one public class per file; files ≤ 300 lines; `build()` methods ≤ 60 lines — extract a private widget *class* (never a `Widget _buildX()` method, which defeats const-rebuild pruning). No business logic, formatting, HTTP call or `DateTime.now()` inside a widget.

## 4. State management — Riverpod 3, code-generated

- Declare providers with `@riverpod` annotation + `riverpod_generator`. No hand-written provider globals.
- Use `Notifier` / `AsyncNotifier` only. `StateProvider`, `StateNotifierProvider` and `ChangeNotifierProvider` are deprecated to `package:riverpod/legacy.dart` — **never import legacy**.
- `AsyncValue` is sealed: consume it with exhaustive pattern matching (`switch (state) { AsyncData(:final value) => …, AsyncError(:final error) => …, AsyncLoading() => … }`). Never `.value!`, never `.hasValue ? ... :` chains.
- `ref.watch` in `build`. `ref.read` only inside callbacks/notifier methods. `ref.listen` for side effects (snackbars, navigation) — never navigate from `build`.
- After every `await` inside a notifier, guard with `if (!ref.mounted) return;`. In widgets, guard with `if (!context.mounted) return;`. This is non-negotiable — it is the top source of "setState after dispose" crashes.
- Providers are `autoDispose` by default (the generator's default); call `ref.keepAlive()` deliberately and document why.
- Use **mutations** for form submission and one-shot side effects so loading/error state survives the button's disposal. Use built-in **automatic retry** (exponential backoff, 200 ms → 6.4 s) rather than hand-rolled retry loops; override it per provider where a failure must surface immediately.
- Opt into **offline persistence** (`riverpod_sqflite`) for providers whose data should survive a cold start. Persisted state must be versioned and migration-safe.
- `select()` on every watch that reads one field of a large object, so unrelated changes don't rebuild.
- Immutability everywhere: `copyWith`, never mutate a list/map in place. No `late` mutable fields in notifiers.

## 5. Data layer

- **Errors never cross a boundary as exceptions.** Repositories return `Result<T, Failure>` (sealed Freezed union: `NetworkFailure`, `AuthFailure`, `ServerFailure`, `CacheFailure`, `ValidationFailure`, `UnknownFailure`). `try/catch` lives in the repository implementation and nowhere else.
- DTO ≠ domain entity. Every API response maps through an explicit mapper. A JSON key change must break exactly one file.
- All timeouts explicit (connect/receive). Cancel in-flight requests on dispose (`CancelToken`). Debounce search/typeahead (≥ 300 ms). Never fire a request in `build`.
- Cache-then-network for anything the user reads: show cached data instantly, revalidate in the background, reconcile with a documented conflict rule. Never show a blank screen when cached data exists.
- Pagination is cursor-based with a page size ≤ 20, prefetch at 80 % scroll, and idempotent retry.

## 6. Navigation

- Single `GoRouter` instance in `app/`, routes declared with `go_router_builder` typed route classes — no raw string paths in feature code.
- Auth gating lives in `redirect` driven by an auth provider + `refreshListenable`. Never gate navigation inside a screen's `initState`.
- `StatefulShellRoute.indexedStack` for bottom-nav/tab shells so each branch keeps its own state and scroll position.
- Deep links configured and tested on Android (App Links), iOS (Universal Links) and Web (real URLs, browser back/forward, refresh-safe, shareable). Unknown routes hit a designed 404 screen, never a red error box.
- Route transitions ≤ 300 ms, platform-appropriate, and consistent across the app.

## 7. Performance budgets — treat as tests, not aspirations

- **Frame budget:** 16.6 ms at 60 Hz, 8.3 ms at 120 Hz. Zero jank frames while scrolling, on release builds, on a low-end Android device.
- Cold start to first meaningful paint: < 2 s mobile, < 3 s web. Web initial WASM payload < 3 MB compressed; everything else deferred.
- Rules: `const` constructors everywhere possible; `ListView.builder`/`SliverList` with `itemExtent` or `prototypeItem` when heights are uniform; `RepaintBoundary` around independently animating subtrees; `AutomaticKeepAliveClientMixin` only where genuinely needed.
- Never wrap large subtrees in `Opacity`, `ClipRRect`, `BackdropFilter` or `ShaderMask` — use `AnimatedOpacity`/`FadeTransition`, `borderRadius` on the decoration, and keep blur regions small. Blur on scroll is a jank source; measure it.
- Images: `cacheWidth`/`cacheHeight` sized to the layout, `cached_network_image` with disk cache, explicit placeholders and error widgets, `precacheImage` for above-the-fold hero art. Never decode a 4000 px asset into a 100 px avatar.
- Animations: prefer implicit (`AnimatedContainer`, `AnimatedSwitcher`) → then `AnimationController` + `AnimatedBuilder` scoped to the smallest subtree → `setState` on a ticker is forbidden. Always `dispose()` controllers. Drive continuous motion from a single controller, not N timers.
- No `Future`/heavy compute on the UI isolate: JSON > 50 KB, image processing, crypto and sorting large lists go through `compute`/`Isolate.run`.
- Verify with DevTools: Performance overlay, raster vs UI thread timings, and `--profile` builds. Widget Previews (stable in 3.47) for fast visual iteration. If you claim something is fast, name the measurement.

## 8. Responsive and adaptive — mobile and web must both be first-class

- Breakpoints: compact < 600, medium 600–1023, expanded ≥ 1024. Layout switches with `LayoutBuilder`; use `MediaQuery.sizeOf(context)` (not the full `MediaQuery.of`) so you don't rebuild on keyboard events.
- No hardcoded pixel heights for text-bearing containers. No `SizedBox` fixed heights that break at `textScaler` 2.0 — test at 0.85, 1.0, 1.5 and 2.0.
- Every scrollable is bounded and safe: `SafeArea`, `SingleChildScrollView` for forms, `resizeToAvoidBottomInset` handled, no yellow/black overflow stripes ever. Long text gets `maxLines` + `TextOverflow.ellipsis` or wraps deliberately.
- Web specifics: keyboard navigation and visible focus rings; hover states on every interactive element; `SelectionArea` for text; browser back = expected back; right-click and text selection not broken; `Scrollbar` shown on desktop widths; content max-width ~1200 px so nothing stretches to 2560 px.
- Adaptive, not uniform: platform-correct scroll physics, dialogs, date pickers and icons via `Theme.of(context).platform`.
- Accessibility is a requirement: semantic labels on icon-only buttons, ≥ 48×48 touch targets, WCAG AA contrast, `MediaQuery.disableAnimations` respected, screen-reader pass on both platforms.

## 9. UI quality and engagement

- One design system in `core/design_system`: colour, typography, spacing (4/8-pt scale), radii, elevation, motion durations and curves as **tokens**. Zero magic numbers and zero raw `Color(0xFF…)` in feature code. `ThemeData` extensions carry them; light and dark are both complete, tested and switchable at runtime.
- Every screen implements four states explicitly: **loading (skeleton/shimmer, never a bare spinner), empty (illustration + one clear action), error (human message + retry), content**. A missing empty state is a bug.
- Motion with intent: 150–250 ms for micro-interactions, 250–350 ms for transitions, `Curves.easeOutCubic`/`easeInOutCubicEmphasized` as defaults. Staggered list entrance ≤ 60 ms offsets, hero transitions on image→detail, animated counters, subtle scale on press, haptics (`HapticFeedback.selectionClick`) for meaningful confirmations. Motion should confirm causality — never decorate for its own sake, never block input.
- Optimistic UI on user actions where safe: reflect the change immediately, reconcile with the server, roll back with an explanatory snackbar on failure.
- Feedback ≤ 100 ms on every tap. No dead zones, no double-fire (disable while in flight), no unlabeled destructive actions.

## 10. Security and data protection

- No secrets, API keys, tokens or endpoints-with-credentials in the client or in `--dart-define` defaults committed to git. Anything the client holds is public — enforce authorization server-side.
- Tokens: access token in memory, refresh token in `flutter_secure_storage` (Keychain / EncryptedSharedPreferences). On **Web, never `localStorage`/`sessionStorage` for tokens** — httpOnly cookies + CSRF token. Single-flight refresh with a queue; force logout and wipe on refresh failure.
- HTTPS only; certificate pinning on mobile for auth and payment endpoints. Validate every server response shape before use.
- Logging: no PII, tokens, request bodies or full URLs with query params in release logs. Strip all `debugPrint`/`print` from release via a logger with level gating. Crash reporting (Crashlytics/Sentry) with a scrubbing hook and explicit user consent where required.
- Local data: nothing sensitive in plain SharedPreferences or unencrypted SQLite. Clear all caches, cookies and secure storage on logout. `flutter build --obfuscate --split-debug-info=…` for release. Set `FLAG_SECURE`/screenshot protection on sensitive screens; clear sensitive fields from the clipboard.
- Input validation on both sides; parameterized queries only; sanitize anything rendered into a WebView or URL. Never `launchUrl` an unvalidated string.
- RBAC is enforced on the server; the client only *hides* UI. Never assume a hidden button is a protected action.

## 11. Errors and observability

- No empty `catch`. No `catch (e) { print(e); }`. Every catch either recovers, converts to a `Failure`, or rethrows with context.
- Global handlers wired in bootstrap: `FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded`, plus an `ErrorWidget.builder` that never shows a red screen to a user in release.
- Structured logging with levels and feature tags. Instrument: cold start, screen render, API latency/error rate, crash-free rate, frame timings via `SchedulerBinding.addTimingsCallback`.

## 12. Testing gates

- Unit tests for every notifier, mapper, use case and `Result` branch — including the error paths. Use `ProviderContainer.test()`, `overrideWithBuild`, `overrideWithValue` and `WidgetTester.container`.
- Widget tests for every screen's four states. **Golden tests** for design-system components and key screens across light/dark × compact/expanded × textScaler 1.0/1.5.
- Integration tests (`integration_test`) for the critical flows: auth, primary conversion path, offline→online recovery.
- Coverage ≥ 80 % on `domain` + `data`, ≥ 60 % overall. No flaky tests; no `pumpAndSettle` on infinite animations; no `Future.delayed` as a synchronization mechanism.
- CI must run: `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos --fatal-warnings`, `dart run build_runner build --delete-conflicting-outputs`, `flutter test --coverage`, and release builds for Android, iOS and `--wasm` web.

## 13. Definition of Done — verify before you report a task complete

1. `flutter analyze --fatal-infos --fatal-warnings` → 0 issues.
2. `dart format` clean; `build_runner` output committed and current.
3. All tests green, new code covered including error paths.
4. Runs correctly on Android, iOS and Web-WASM; scroll and animations profiled with no jank frames.
5. Verified at textScaler 2.0, at 360 px width and at 1920 px width; light and dark; keyboard-only navigation on web.
6. Loading, empty, error and content states all present and designed.
7. No secrets, no PII in logs, no unencrypted sensitive storage, tokens handled per §10.
8. No `TODO`, no commented-out code, no unused imports, no leftover debug prints, no dead files.
9. Every disposable disposed: controllers, subscriptions, `CancelToken`, focus nodes, tickers.

## 14. Forbidden

`setState` in a widget that a Riverpod provider should own · `GlobalKey<State>` for cross-widget access · `Provider.of`/`InheritedWidget` hand-rolled for app state · `dart:html` · `localStorage` for tokens · business logic in widgets · `Widget _buildX()` methods · unbounded `Column` inside `Column` · `Expanded` inside an unbounded parent · `MediaQuery.of(context).size` where `sizeOf` works · `.then()` chains where `async/await` reads clearer · `dynamic` in public APIs · magic numbers and inline colours · silent catches · `print` in release · fixed heights around text · third-party packages last published > 12 months ago without justification · generated files edited by hand · `pubspec` version ranges of `any`.

## 15. How you must respond

1. **Plan before code.** State the approach, files touched, packages added (with versions and reason), and trade-offs. If the request is ambiguous, ask up to three specific questions first.
2. **Deliver complete, compiling code.** Full file contents or precise diffs — never `// rest of the code here`, never pseudo-code.
3. **Show the layering.** When you add a feature, name where each piece lands in the §3 tree.
4. **Self-review before finishing.** Walk §13 explicitly and report which items you verified versus which the user must verify on a device. Do not claim performance or platform behaviour you did not test.
5. **Flag risk.** If a request would create a leak, a jank source, an accessibility break or a security hole, refuse the shortcut and give the correct implementation instead.
6. Be concise in prose. The code and the checklist are the deliverable.

---

# Part B — This project

The standard above is generic. Everything below is specific to this repository and is **not** superseded by it.

## B1. What the app is

Vistar KRA — a quarterly performance-review app. Employees hold weighted KRAs; a
per-organisation **review flow** decides who rates them:

- **`STANDARD`** — employee self-rates → reporting manager / HR / Accounts rate their
  assigned KRAs → management signs off → incentive payout. The default, and in production.
- **`ADMIN_ONLY`** — the same pipeline with the self-rating removed. HR rates its KRAs,
  Accounts rates its KRAs, **management rates every remaining KRA**, then signs off.

The single place those diverge is
[`lib/features/reviews/data/models/review_flow.dart`](lib/features/reviews/data/models/review_flow.dart).
For `STANDARD` it returns `ReviewStage.actorRoles` unchanged — the same object, not a
copy — so an organisation on the standard flow runs exactly the code it ran before flows
existed. **Derive gates from the model; never restate a role list.** Restating is what
caused `management` to go missing from the sign-off, Accounts to be dropped from
`ADMIN_ONLY`, and `hrAdmin` to bypass the `roleTiers` narrowing. All three were real bugs.

**One reviewer per KRA.** Each KRA row carries exactly one `reviewerGroup`, and the sheet
draws one Review column per month at that seat. Two roles never rate the same KRA.

## B2. Backend contract

- Base URL in [`lib/core/api/api_constants.dart`](lib/core/api/api_constants.dart). All
  three env labels currently alias the same Render-hosted test backend.
- Envelopes: `{ success: true, data, meta?: { page, limit, total, totalPages } }` or
  `{ success: false, error: { code, message } }`. Parsers in
  [`core/api/envelope.dart`](lib/core/api/envelope.dart) — `unwrapObject`, `unwrapList`,
  `unwrapPaged`, `unwrapMeta`.
- Auth: Bearer on every request except `noAuthEndpoints`. 401 → `RefreshInterceptor`
  refreshes once and retries, mutex-guarded. On `TOKEN_INVALID` / `REFRESH_TOKEN_REUSE`
  or refresh failure, forced logout fires.
- **Decimals arrive as strings** (`"7000.00"`) — `JsonParse.parseDouble` takes both forms.
  Dates are ISO 8601 — `JsonParse.parseDate` returns `DateTime?`.
- **Dual-read models.** Live payloads sometimes nest under `employee.*` / `reviewCycle.*`
  where the spec was flat, so models read the live name first with a flat fallback. See
  `team_member.dart`, `manager_review_detail.dart`, `pending_action.dart`,
  `previous_review.dart`. Any move to code-generated models must preserve this tolerance.
- **Multi-tenancy: the JWT claim is the boundary.** Every backend query filters by the
  `organizationId` claim, never a request parameter. `/auth/me` returns the employee row's
  **home** org; the token claim is the **acting** org, and they diverge after an org switch.
  Every `*RepositoryProvider` watches
  [`currentOrgIdProvider`](lib/core/providers/org_scope_provider.dart) so one dependency
  edge invalidates the whole graph on a switch. `authRepositoryProvider` is the documented
  exemption — watching it would close a dependency cycle.
- The backend's compiled `dist/*.js` is the **deployed artifact** (tracked in git, no `tsc`
  step). Patch scripts for it live in [`docs/`](docs/) and are dry-runnable.
- The client and server keep **separate** tables of who may rate which stage, and they
  drift. See [`docs/RATING_ROLE_DIVERGENCE.md`](docs/RATING_ROLE_DIVERGENCE.md).

## B3. Brand

Primary `#6B1F7C` purple · accents `#FF6B1A` orange, `#FFB800` yellow, `#E63946` red ·
Plus Jakarta Sans via `google_fonts` · currency Indian format (`₹1,37,835.00`) via `intl` ·
dates `d MMM yyyy` ("12 May 2026"). Tokens live in
[`core/constants/app_colors.dart`](lib/core/constants/app_colors.dart); all user-facing
strings in [`core/constants/app_strings.dart`](lib/core/constants/app_strings.dart).

## B4. Live test credentials

All passwords `Vistar@123`.

| Role | Email | Notes |
| --- | --- | --- |
| HR_ADMIN | `hr.admin@vistar.test` | note the dot |
| MANAGER | `manager@vistar.test` | manages emp1–emp3 |
| EMPLOYEE | `emp1@vistar.test` | E1, review state DRAFT |
| EMPLOYEE | `emp2@vistar.test` | E1, `EMPLOYEE_SUBMITTED_ALL` |
| EMPLOYEE | `emp3@vistar.test` | M1, `FINALIZED` |

Login accepts **either** email or `employee_code`. The auth rate limiter is **10 attempts
per 15 minutes per IP** — reuse one token when probing rather than logging in repeatedly.

## B5. How to run

```bash
flutter pub get
flutter analyze          # must be 0 issues
flutter test             # must end "All tests passed!"
flutter run -d chrome
flutter build web --release
```

The backend is on Render's free tier: the first request after ~15 min of inactivity takes
30–60 s. Don't file a "loading forever" bug without waiting it out.

## B6. Where to read next

- [USER_MANUAL.md](USER_MANUAL.md) — what each screen does, role by role.
- [TESTING_GUIDE.md](TESTING_GUIDE.md) — manual test plan with stable case IDs.
- [docs/RATING_ROLE_DIVERGENCE.md](docs/RATING_ROLE_DIVERGENCE.md) — the two role tables.
- [docs/BACKEND_RBAC_FINDINGS.md](docs/BACKEND_RBAC_FINDINGS.md) — role-enforcement audit.

---

# Part C — Deviation register

**Measured 2026-09-09** against Flutter 3.47.2 stable, 285 files in `lib/`, 683 passing
tests, `flutter analyze --fatal-infos --fatal-warnings` clean, `dart format` clean.

The toolchain in §2 is partly adopted. An agent must not assume an API that is not in
`pubspec.yaml`, and must not begin a ❌ migration below without being asked. Write **new**
code to the standard; leave existing code alone unless the task is that migration.

| § | Standard requires | This repo | Scale of change |
| --- | --- | --- | --- |
| 2 | Flutter 3.47 stable | ✅ 3.47.2 | — |
| 2 | `package:web`, no `dart:html` | ✅ `web 1.1.1`, 0 `dart:html` | — |
| 2 | Exact version pins, never `any` | ✅ all 15 direct deps pinned exactly | — |
| 2 | Web ships `--wasm` | ✅ builds; `main.dart.wasm` 1.24 MB gz | — |
| 10 | Release builds `--obfuscate --split-debug-info` | ✅ Android APK + arm/arm64/x64 symbols | — |
| 13.4 | Runs on Android, iOS, Web-WASM | ⚠️ Android ✅, Web-WASM ✅, **iOS unverified** (needs macOS) | — |
| 2 | `flutter_riverpod` 3.4.x + codegen | ❌ `2.6.1`, hand-written providers | codebase-wide |
| 2 | `go_router` 18.x typed routes | ❌ `13.2.5`, `AppRoutes` string constants | codebase-wide |
| 2 | `freezed` 4 + `json_serializable` on every model | ❌ neither; hand-written `fromJson` | codebase-wide |
| 2 | `very_good_analysis` 10.3.x | ❌ `flutter_lints 3.0.2` | one file + fallout |
| 2 | `material_ui` / `cupertino_ui` packages | ❌ SDK `package:flutter/material.dart` in 136 files | codebase-wide |
| 2 | `drift` / `sqflite` local cache | ❌ none; `shared_preferences` for drafts only | new capability |
| 3 | `data` / `domain` / `presentation` | ❌ no `domain/`; 0 of 5 features have one | codebase-wide |
| 3 | Files ≤ 300 lines | ❌ 52 files over; largest 4596 (`quarterly_kra_sheet_screen.dart`) | per-file |
| 4 | No legacy providers | ❌ 22 `StateNotifierProvider` / `StateProvider` sites | with the 2→3 migration |
| 4 | No `.value!` on `AsyncValue` | ✅ 0 bang operators anywhere in `lib/` | — |
| 4 | Exhaustive `AsyncValue` pattern matching | ❌ 53 `.when()` / `.maybeWhen()` (`main.dart` converted) | mechanical |
| 5 | `Result<T, Failure>` sealed union | ❌ `ApiError` thrown, caught at the UI edge | codebase-wide |
| 9 | Tokens in `core/design_system` on `ThemeData` extensions | ⚠️ equivalent tokens in `core/constants/`; no spacing/radii/motion tokens | rename + extend |
| 10 | No `debugPrint` reaching release | ✅ level-gated + scrubbed via `AppLog` | — |
| 11 | Four global error handlers | ✅ all four in `lib/app/bootstrap.dart` | — |
| 11 | Structured logging with levels + tags | ✅ `core/observability/app_logger.dart` | — |
| 11 | Crash reporting with a scrubbing hook | ⚠️ `AppLog.sink` is the hook; no reporter attached | one file |
| 12 | CI running format/analyze/test/builds | ✅ `.github/workflows/ci.yaml` | — |
| 12 | Coverage ≥ 80% data, ≥ 60% overall | ❌ **16.1% overall**, data 39.9%, providers 5.2%, screens 8.7% | large |
| 12 | Golden tests | ❌ 0 | new capability |
| 12 | `integration_test` | ❌ no directory | new capability |
| 14 | No `Widget _buildX()` methods | ❌ 66 sites (`main.dart` converted) | per-file |

## `flutter build` can fail and still exit 0 — assert the artifact

Observed twice on this machine, and the reason every build gate in `ci.yaml` checks for a
file rather than trusting `$?`:

```
flutter build web --release --wasm   -> "Error: Failed to compile application for the Web."   exit 0
flutter build apk --release          -> "Gradle task assembleRelease failed with exit code 1"  exit 0
```

A conventional CI step would have reported success having produced nothing. Do not remove
those assertions.

The Android failure was separately instructive: it was stale Kotlin incremental caches
under `build/`, left behind by the `file_picker` 8→12 plugin swap
(`Could not close incremental caches in build/android_file_picker/kotlin/...`). A
`flutter clean` fixed it and the release build then produced a 57.2 MB APK with symbols
for all three ABIs. **After any plugin version change, `flutter clean` before trusting an
Android build.**

## What §2's WASM requirement actually cost

The cause of the web failure was never this app's code — the `dart:html` count really was
zero. It was three plugins pulling it in transitively, and clearing them forced three
major upgrades:

| Package | Was | Now | Why |
| --- | --- | --- | --- |
| `flutter_secure_storage` | 9.2.4 | **11.0.0** | 9.x's web impl imports `dart:html` + `dart:js_util` |
| `connectivity_plus` | 5.0.2 | **7.3.1** | 5.x's web impl imports `dart:html` |
| `file_picker` | 8.3.7 | **12.2.0** | 8.x pins `win32 ^5.9.0`; secure storage 11 needs `^6.0.1` |

Each was survivable only because the surface was tiny: secure storage and connectivity are
each wrapped in exactly one file, and `file_picker` had two call sites. The API breaks were
`AndroidOptions(encryptedSharedPreferences:)` removed (11.x makes the strong AES-GCM +
RSA-OAEP path the default, so nothing was lost), and `FilePicker.platform` becoming static
with `withData:` superseded by `PlatformFile.readAsBytes()`.

## Corrections to the first measurement

- The "5 `.value!`" row was wrong. Those were `RowScore.value!` — nullable-`double`
  dereferences after explicit guards, not §4's `AsyncValue.value!` misuse, of which there
  were **zero**. They have since been rewritten to promote through a local, so `lib/`
  now contains no bang operators at all.
- `ApiLoggerInterceptor` was already compliant: it self-gates on `kDebugMode` and redacts
  sensitive headers and body keys. The release-logging gap was the ~13 bare `debugPrint`
  calls elsewhere, since `debugPrint` is **not** stripped from release builds.
- `user.dart`'s `debugPrint` sits inside `assert(() { … }())`, which *is* stripped.

**Already strong, and not to be regressed:**

- Multi-tenant isolation via the `currentOrgIdProvider` dependency edge (§10's tenancy
  concern), with tests that fail if a repository provider stops watching it.
- **Source-level regression tests for bug _classes_** — they scan `lib/` for a defect
  shape rather than an instance, and each was validated by reintroducing the bug and
  confirming the test named the exact file and line. Every class had multiple live
  instances when found: shell-route pushes, unscoped providers, raw exception dumps in the
  UI, `/auth/me` field erasure. The standard does not describe this pattern; keep it.
- `userFacingError` at every catch site, so an `ApiError` dump never reaches a user.
- Mutex-guarded single-flight token refresh with forced logout on failure (§10).

## The review month is the PREVIOUS calendar month

A month is rated once it has **ended**: through September you rate August. One
definition — `ReviewPeriod.openForRating`, with `isRatableOn` and
`clampToRatable` beside it in
[`monthly_review.dart`](lib/features/reviews/data/models/monthly_review.dart).
Never re-derive it.

The deadline schedule is the proof this is the design rather than a preference:
self-rating is due on the **10th**, which only makes sense as the 10th of the
month *after* the one being rated.

Six places used to answer this independently, and disagreed. Two were display —
the home card rendered the API's `monthLabel` verbatim while the banner used a
different path, so fixing one left the other showing September. Four were the
**write** path: `isFutureMonth` asked "has this month *started*", so the live
month's cells were editable, and a score for an unfinished month was persisted,
submittable, and counted toward the incentive.

The manager matrix was the worst of them. Every cycle month is seeded `OPEN`,
and `isComplete` treated OPEN as *required*, so submit stayed disabled until the
manager invented a rating for a month still in progress — and that number was
POSTed. Cells now go through
[`MonthlyScore.isRatableOn`](lib/features/manager/data/models/monthly_score.dart).
Because the server's `MANAGER_RATED_ALL` transition is cycle-level and
all-or-nothing, the submit CTA is withheld until the cycle's last month closes,
with dated copy; ratings auto-save throughout, so only the transition waits.

Two traps worth keeping in mind:

- `copyWith` **must** carry `monthDate`. It runs on every keystroke, and
  dropping it nulls the date on first edit, after which `isRatableOn` refuses
  the cell and locks the manager out of the matrix.
- "Every ratable cell is rated" is **vacuously true** when nothing is ratable
  yet, which would enable submit on an empty review. `isComplete` therefore
  also requires that at least one cell was ratable.

Server-side root cause: `findCurrentMonth` in
`dist/features/employee/employee.service.js` still matches *today's* month.
Patch: [`docs/install_review_month_shift.mjs`](docs/install_review_month_shift.mjs),
verified 2/6 → 6/6 including the January rollover. The client **clamps** whatever
the server sends, so the screens are correct without it.

## The KRA sheet's COLUMNS are flow-shaped, not just its gates

The flow decides which stages exist, so it also decides which columns exist. On
`ADMIN_ONLY` the employee never rates, and the three per-month Self columns plus
the Qtr Self column were a dash in every row and a 0% in the totals — 266 px of
dead grid that pushed the two live columns off the right edge, and a payout card
reporting a self average of 0% next to a real final average, which reads as "the
employee scored nothing" rather than "this does not apply". The same was true of
the Reason & proof panel's Employee slot, which said "No entry" for the life of
the quarter.

One gate, `stageIsInFlow(ReviewStage.selfRating, flow)`, drives all of it —
`_GridState._showSelf`. Not `flow == adminOnly`: **four** builders have to agree
(header, KRA row, totals row, and `_totalWidth`), and

> a column hidden in one builder while its width is still charged in another
> misaligns every value in that row against its own header — silently, with no
> overflow error on a wide screen.

`quarterly_kra_sheet_self_columns_test.dart` measures the summed cell width of
each rendered row and asserts they are equal and equal to `_totalWidth`.
Validated by reintroducing both halves: a non-flow-aware `_totalWidth` and a
single dropped guard, which showed up as `Set:[1016.0, 1226.0]`.

`_Sheet` now takes the resolved `ReviewFlow`, not the `ReviewScope`. It read
nothing else off the scope and re-derived `scope?.reviewFlow ?? standard` at
seven call sites — B1's drift, and the reason the widget-test hook could only
ever exercise the standard pipeline (it passed `scope: null`).

## A KRA row has a DIFFERENT id in every month

`monthly_review_rows.id` is `randomUUID()` per row **per review**, so one KRA
carries three ids across a quarter — while the sheet takes its canonical row
list from the first month present. Any per-month read or write handed the
canonical id therefore addresses a row that month does not contain.

The server does not complain. `writeRowScores` is

```sql
INSERT INTO kra.monthly_row_scores AS s (...) SELECT ...
WHERE EXISTS (SELECT 1 FROM kra.monthly_review_rows mrr
              WHERE mrr.id = $2 AND mrr.review_id = $6 AND <reviewer guard>)
```

so a foreign row id inserts **zero rows and returns 200 OK**. The user sees no
error and no saved data.

This has now bitten twice. First the score cells — fixed by resolving
`_monthRowId` once in `_scoreCell`. Then the Reason & Proof panel, which was
missed: an employee's August reason was discarded silently while July worked.
Resolve the id **once per month card** (`_monthCard`) and pass it down; do not
patch call sites individually.

Doing it at the source is not just tidier, it is the only safe shape. The same
id feeds `_currentScore`, which matches by **exact id with no fallback**. Fix
only the save key and `current` stays null, so the save then writes
`value: null` over the stored score — `DO UPDATE SET value = EXCLUDED.value` is
unconditional — and, with no stored file seeded into the dialog,
`clearProofFile: true` over the attachment. A one-line fix in the wrong place
converts a silent no-op into silent destruction.

Note the asymmetry that hides this: `_rowIn` is **tolerant** (id → displayOrder
→ name key), so reads keep working and only writes fail. A test that asserts
what renders will pass with the bug present — `quarterly_kra_sheet_evidence_
rowid_test.dart` therefore asserts the invariant *no review is asked for a row
id it does not contain*, and gives all three months different ids. Validated by
reintroducing the bug: `Set:['r-aug asked for row-uuid-jul', 'r-sep asked for
row-uuid-jul']`.

## Proof attachments: the cap lives in three places

Raw client cap `_maxProofBytes` (5 MB) → base64 is 4/3 of raw, so 5 MB becomes
6,990,508 bytes → server `PROOF_FILE_MAX_BASE64` (7 MB) → `express.json({
limit: '10mb' })`. Change one and check the other two. The client's error copy
derives its number from the constant rather than restating it, because the old
copy hardcoded "~700 KB" and would have quoted a limit it no longer enforced.

The two server constants are in the repo but were **not deployed** as of
2026-09-10, so against the live API a file over ~700 KB is rejected by the
server. The two rejections do not read alike: zod's carries a real message,
a raw 413 from the body parser is not in the app's JSON envelope and falls back
to "Could not save. Please try again."

**Open, deliberately unresolved** (product decisions, not code debt):

- `HR_ADMIN` holds the Accounts seat on the client but not the server —
  [`docs/RATING_ROLE_DIVERGENCE.md`](docs/RATING_ROLE_DIVERGENCE.md).
- Weighted totals renormalise over scored rows only, so an unrated KRA vanishes from the
  denominator instead of scoring zero. Affects payout in **both** flows.

When you touch any row above, update it. A register that goes stale is worse than none —
it is what let §2 read as though `freezed` and Riverpod 3 were already here.
