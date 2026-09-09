import '../constants/app_strings.dart';
import 'api_error.dart';

/// Turns any thrown object into text that is safe and useful to show a user.
///
/// Exists because error UIs across the app were rendering `e.toString()`, which
/// on an [ApiError] produces its DEBUG form and put things like this on screen:
///
///     ApiError(ApiErrorType.notFound, code=RES_001, status=404,
///              msg="We couldn't find what you were looking for.")
///
/// [ApiError.message] is already sanitised, polite prose written for the end
/// user — the debug form buried it inside noise the user cannot act on.
///
/// Prefers [ApiError.combinedMessage], which folds in per-field validation
/// details when the backend sent any; those are almost always more specific
/// than the generic "Validation failed".
String userFacingError(Object error, {String? notFoundMessage}) {
  if (error is! ApiError) return AppStrings.errorGeneric;

  // A 404 on an org-scoped resource usually is not a failure at all — it is
  // tenant isolation working. The caller knows what it was fetching, so it can
  // say something true instead of "we couldn't find it".
  if (error.statusCode == 404 && notFoundMessage != null) {
    return notFoundMessage;
  }
  return error.combinedMessage;
}
