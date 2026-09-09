import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/org_scope_provider.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/hr_dashboard_models.dart';
import '../../data/repositories/api_audit_log_repository.dart';
import '../../data/repositories/audit_log_repository.dart';
import '../../../../core/observability/app_logger.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  // Org-scoped: recreated whenever the caller switches organisation, which
  // invalidates every provider that watches this repository. Without it,
  // cached lists from the previous tenant would be served under the new
  // tenant's name. See core/providers/org_scope_provider.dart.
  ref.watch(currentOrgIdProvider);
  return ApiAuditLogRepository(dio: ref.read(dioProvider));
});

class AuditLogListState {
  final List<HrActivityEntry> entries;
  final int page;
  final int total;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final String? error;

  const AuditLogListState({
    this.entries = const [],
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  AuditLogListState copyWith({
    List<HrActivityEntry>? entries,
    int? page,
    int? total,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
  }) {
    return AuditLogListState(
      entries: entries ?? this.entries,
      page: page ?? this.page,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

class AuditLogListController extends StateNotifier<AuditLogListState> {
  final AuditLogRepository _repo;
  static const int _pageSize = 20;

  AuditLogListController(this._repo) : super(const AuditLogListState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(
      isInitialLoading: true,
      entries: const [],
      page: 0,
      error: null,
    );
    try {
      final pageData = await _repo.fetchLogs(page: 1, pageSize: _pageSize);
      state = AuditLogListState(
        entries: pageData.entries,
        page: 1,
        total: pageData.total,
        hasMore: pageData.entries.length < pageData.total,
        isInitialLoading: false,
      );
    } on ApiError catch (e) {
      state = state.copyWith(isInitialLoading: false, error: e.message);
    } catch (e, st) {
      assert(() {
        AppLog.e('hr.audit', 'audit log parse failed',
            error: e, stackTrace: st);
        return true;
      }());
      state = state.copyWith(
        isInitialLoading: false,
        error: AppStrings.errorGeneric,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isInitialLoading) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = state.page + 1;
      final pageData = await _repo.fetchLogs(page: next, pageSize: _pageSize);
      final combined = [...state.entries, ...pageData.entries];
      state = state.copyWith(
        entries: combined,
        page: next,
        total: pageData.total,
        hasMore: combined.length < pageData.total,
        isLoadingMore: false,
      );
    } on ApiError {
      state = state.copyWith(isLoadingMore: false);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
      rethrow;
    }
  }
}

final auditLogListProvider = StateNotifierProvider.autoDispose<
    AuditLogListController, AuditLogListState>((ref) {
  return AuditLogListController(ref.watch(auditLogRepositoryProvider));
});
