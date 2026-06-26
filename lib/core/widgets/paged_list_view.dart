import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import 'shimmer_skeletons.dart';
import 'slow_load_hint.dart';

/// Infinite-scroll list that adheres to the CLAUDE.md convention:
///
///   - Every list uses [PagedListView] with shimmer at end.
///
/// Owns: the scroll controller, load-more trigger, trailing shimmer,
/// pull-to-refresh, and the empty / error overlays.
///
/// Does NOT own: data fetching. The parent supplies a state snapshot
/// + callbacks; this widget only orchestrates the UI.
///
/// Designed to be drop-in compatible with the existing HR list
/// controllers (`EmployeeListController`, `MyReviewListController`)
/// which already expose `hasMore`, `isLoadingMore`, `loadMore()`, and
/// `refresh()`.
class PagedListView<T> extends StatefulWidget {
  /// Items currently in memory. Combine all loaded pages into this list
  /// — the widget renders them in order.
  final List<T> items;

  /// Builder for each item row.
  final Widget Function(BuildContext context, int index, T item) itemBuilder;

  /// Optional separator between rows.
  final IndexedWidgetBuilder? separatorBuilder;

  /// True while the very first page is loading. Shows [skeletonItemCount]
  /// shimmer rows full-screen.
  final bool isInitialLoading;

  /// True when more pages are being fetched in the background. Shows
  /// trailing shimmer rows below the last loaded item.
  final bool isLoadingMore;

  /// True if there are pages still to fetch — drives the load-more
  /// trigger and the trailing shimmer.
  final bool hasMore;

  /// Error message (typically the result of mapping an [ApiError])
  /// shown when the initial load fails and the list is empty.
  final String? initialError;

  /// Callback invoked when the scroll position approaches the bottom.
  /// Should be idempotent — the widget guards against duplicate calls
  /// via [isLoadingMore], but a defensive parent helps too.
  final VoidCallback onLoadMore;

  /// Pull-to-refresh handler. Wrap with the same notifier `.refresh()`
  /// the screen uses; the widget pipes the future through
  /// [RefreshIndicator].
  final Future<void> Function() onRefresh;

  /// Optional retry hook for the initial-error state. Defaults to
  /// invoking [onRefresh] if not supplied.
  final Future<void> Function()? onRetry;

  /// Builder for the empty state (items.isEmpty after a successful load).
  /// Defaults to a generic "Nothing here yet" surface.
  final WidgetBuilder? emptyBuilder;

  /// Padding around the list itself. Defaults to symmetric horizontal 16.
  final EdgeInsetsGeometry padding;

  /// Number of skeleton rows to render during the initial load.
  final int skeletonItemCount;

  /// Distance from the bottom (in pixels) at which to fire [onLoadMore].
  /// 400 keeps the trigger comfortable on long lists without firing
  /// repeatedly while idle near the end.
  final double loadMoreThreshold;

  const PagedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.onRefresh,
    this.separatorBuilder,
    this.isInitialLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.initialError,
    this.onRetry,
    this.emptyBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.skeletonItemCount = 6,
    this.loadMoreThreshold = 400,
  });

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (widget.isLoadingMore || !widget.hasMore) return;
    final position = _controller.position;
    if (position.pixels >=
        position.maxScrollExtent - widget.loadMoreThreshold) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primaryPurple,
      onRefresh: widget.onRefresh,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (widget.isInitialLoading) {
      // index 0 is the slow-load hint (renders nothing until ~7s); the
      // rest are skeleton rows.
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: widget.skeletonItemCount + 1,
        itemBuilder: (_, i) {
          if (i == 0) return const SlowLoadHint();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: ListItemSkeleton(),
          );
        },
      );
    }
    if (widget.initialError != null && widget.items.isEmpty) {
      return _ErrorView(
        message: widget.initialError!,
        onRetry: widget.onRetry ?? widget.onRefresh,
      );
    }
    if (widget.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: widget.emptyBuilder?.call(context) ?? const _DefaultEmpty(),
          ),
        ],
      );
    }

    // Trailing shimmer placeholder while a load-more is in flight.
    final trailing = widget.hasMore ? 1 : 0;
    final separator = widget.separatorBuilder;
    if (separator != null) {
      return ListView.separated(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: widget.items.length + trailing,
        separatorBuilder: (ctx, i) {
          if (i >= widget.items.length - 1) {
            return const SizedBox.shrink();
          }
          return separator(ctx, i);
        },
        itemBuilder: (ctx, i) {
          if (i >= widget.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: ListItemSkeleton(),
            );
          }
          return widget.itemBuilder(ctx, i, widget.items[i]);
        },
      );
    }

    return ListView.builder(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: widget.padding,
      itemCount: widget.items.length + trailing,
      itemBuilder: (ctx, i) {
        if (i >= widget.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: ListItemSkeleton(),
          );
        }
        return widget.itemBuilder(ctx, i, widget.items[i]);
      },
    );
  }
}

class _DefaultEmpty extends StatelessWidget {
  const _DefaultEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 52,
                color: AppColors.textMuted,
              ),
              SizedBox(height: 14),
              Text(
                'Nothing here yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
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
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(AppStrings.commonRetry),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryPurple,
            ),
          ),
        ),
      ],
    );
  }
}
