# My Review mode

This mode reuses screens from `lib/features/employee/`:

| Route                              | Reused screen                                                          |
| ---------------------------------- | ---------------------------------------------------------------------- |
| `/manager/review/home`             | `EmployeeHomeScreen`                                                   |
| `/manager/review/self-rate`        | `SelfRateScreen` (+ the rest of the self-rate flow)                    |
| `/manager/review/history`          | `MyReviewsHistoryScreen` (+ `ReviewDetailScreen` on the detail route)  |
| `/manager/review/profile`          | `MyProfileScreen` (+ `EditProfileScreen`, `MyReportingTreeScreen`)     |

The screens themselves do not need any manager-specific awareness —
they're already authenticated by token and the backend serves the
right data automatically. **Do not duplicate them here.**

Anything manager-mode-specific (chrome, the active-tab accent
colour) lives in `my_review_shell.dart`; everything else delegates.
