/// App-wide runtime configuration.
///
/// Centralises switches that change *behaviour*, not just styling —
/// chiefly the mock-vs-live API toggle that lets the app boot without
/// a backend during development.
///
/// Defaults are tuned for "ergonomic local dev":
///   - [useMockApi] = `true` — all `*RepositoryProvider`s return the
///     mock implementation instead of the API-backed one. Flip this
///     to `false` (or override via `--dart-define`) to point at the
///     real backend.
///
/// Override at run-time via the build flag:
///
/// ```bash
/// flutter run --dart-define=USE_MOCK_API=false
/// ```
///
/// The flag is a compile-time constant so the unused branch tree-
/// shakes out of release builds — keeping the mock repos in the
/// debug-only code path.
class AppConfig {
  AppConfig._();

  /// Default: mock. Override via `--dart-define=USE_MOCK_API=...`.
  static const bool useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: true,
  );
}
