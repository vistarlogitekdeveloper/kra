import '../../../../core/api/json_parse.dart';

/// Detail block returned in `manager-rate` responses when the scores
/// were saved but the review state didn't progress
/// (`transitioned: false`). Each known code maps to a plain-English
/// message via the `transition_error_message_mapper.dart` utility.
class TransitionError {
  /// Stable error code (e.g. `INCOMPLETE_AFTER_COPY`, `MONTH_LOCKED`).
  final String code;

  /// Raw backend message — surfaced as a fallback when the mapper
  /// has no known translation for [code].
  final String message;

  /// Optional structured detail (e.g. list of missing items by KRA
  /// name). Carried as a free-form map so future backend additions
  /// don't break the model.
  final Map<String, dynamic>? detail;

  const TransitionError({
    required this.code,
    required this.message,
    this.detail,
  });

  factory TransitionError.fromJson(Map<String, dynamic> json) =>
      TransitionError(
        code: JsonParse.parseString(json['code']) ?? 'UNKNOWN',
        message: JsonParse.parseString(json['message']) ??
            'Review could not be finalised.',
        detail: JsonParse.parseMap(json['detail']),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'detail': detail,
      };
}
