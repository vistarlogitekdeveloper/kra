import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';

/// Renders an [AsyncValue] with all three states (loading / data / error)
/// in one place. The CLAUDE.md convention mandates that every async
/// screen uses this wrapper rather than calling `.when` ad-hoc — that
/// way a screen can't accidentally drop a state and ship a blank UI.
///
/// Defaults:
///   - loading → a centred [CircularProgressIndicator] in brand purple,
///     unless [loadingBuilder] is supplied (e.g. a shimmer skeleton)
///   - error   → a centred message + Retry button, calling [onRetry]
///     if supplied (otherwise the button is hidden)
///   - data    → calls [dataBuilder]
///
/// Designed for sections that don't need pull-to-refresh themselves
/// — for full-screen "loadable lists" the parent owns the
/// [RefreshIndicator] and just passes data through.
///
/// Usage:
/// ```dart
/// AsyncValueView<MyData>(
///   value: ref.watch(myProvider),
///   loadingBuilder: () => const DashboardCardSkeleton(),
///   onRetry: () => ref.invalidate(myProvider),
///   dataBuilder: (data) => MyContent(data: data),
/// );
/// ```
class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) dataBuilder;
  final WidgetBuilder? loadingBuilder;
  final VoidCallback? onRetry;

  /// Optional override for the error-state widget. Receives the
  /// underlying error so callers can format domain-specific messages.
  final Widget Function(Object error, StackTrace? stack)? errorBuilder;

  const AsyncValueView({
    super.key,
    required this.value,
    required this.dataBuilder,
    this.loadingBuilder,
    this.onRetry,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () =>
          loadingBuilder?.call(context) ?? const _DefaultLoading(),
      error: (e, st) =>
          errorBuilder?.call(e, st) ??
          _DefaultError(error: e, onRetry: onRetry),
      data: dataBuilder,
    );
  }
}

class _DefaultLoading extends StatelessWidget {
  const _DefaultLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(color: AppColors.primaryPurple),
      ),
    );
  }
}

class _DefaultError extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const _DefaultError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 14),
              const Text(
                AppStrings.errorGeneric,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(AppStrings.commonRetry),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryPurple,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
