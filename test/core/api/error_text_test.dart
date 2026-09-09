import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/api/error_text.dart';
import 'package:vistar_app/core/constants/app_strings.dart';

/// Guards the user-facing text of API failures.
///
/// Error UIs used to render `e.toString()`, which on an [ApiError] emits its
/// DEBUG form and put this on screen:
///
///     ApiError(ApiErrorType.notFound, code=RES_001, status=404,
///              msg="We couldn't find what you were looking for.")
///
/// The useful sentence was there all along — buried inside noise the user
/// cannot act on. 13 screens did it.
void main() {
  group('userFacingError', () {
    test('returns the sanitised message, never the debug form', () {
      const e = ApiError(
        type: ApiErrorType.notFound,
        code: 'RES_001',
        message: "We couldn't find what you were looking for.",
        statusCode: 404,
      );
      final text = userFacingError(e);
      expect(text, "We couldn't find what you were looking for.");
      expect(text, isNot(contains('ApiError(')));
      expect(text, isNot(contains('code=')));
      expect(text, isNot(contains('ApiErrorType')));
    });

    test('prefers field errors, which are more specific than the generic', () {
      const e = ApiError(
        type: ApiErrorType.validation,
        code: 'VAL_001',
        message: 'Validation failed',
        statusCode: 400,
        fieldErrors: {
          'slug': ['That slug is already taken.'],
        },
      );
      expect(userFacingError(e), 'That slug is already taken.');
    });

    test('a 404 uses the caller\'s explanation when one is supplied', () {
      // Tenant isolation reads as a 404, so the screen that knows what it was
      // fetching can say something true instead of "we could not find it".
      const e = ApiError(
        type: ApiErrorType.notFound,
        code: 'RES_001',
        message: "We couldn't find what you were looking for.",
        statusCode: 404,
      );
      expect(
        userFacingError(e, notFoundMessage: AppStrings.employeeNotInThisOrg),
        AppStrings.employeeNotInThisOrg,
      );
    });

    test('a non-404 ignores the not-found explanation', () {
      const e = ApiError(
        type: ApiErrorType.server,
        code: 'SERVER_ERROR',
        message: 'Our servers are having trouble.',
        statusCode: 500,
      );
      expect(
        userFacingError(e, notFoundMessage: 'should not be used'),
        'Our servers are having trouble.',
      );
    });

    test('a non-ApiError falls back to the generic message', () {
      // A TypeError from a schema mismatch must not be shown verbatim.
      expect(userFacingError(TypeError()), AppStrings.errorGeneric);
      expect(userFacingError('a bare string'), AppStrings.errorGeneric);
    });
  });

  group('no screen renders a raw exception', () {
    test('lib/ contains no `message: e.toString()`', () {
      // Source-level: the damage is only visible at runtime, on whichever
      // screen happens to fail, so the only reliable check is every call site.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (RegExp(r'message:\s*e(rror)?\.toString\(\)').hasMatch(line) ||
              RegExp(r"""Text\(\s*'\$e'\s*\)""").hasMatch(line)) {
            offenders.add('${entity.path.replaceAll(r'\', '/')}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'These render an exception verbatim, which shows the user '
            'ApiError(...) debug output. Use userFacingError(e):\n'
            '  ${offenders.join('\n  ')}',
      );
    });
  });
}
