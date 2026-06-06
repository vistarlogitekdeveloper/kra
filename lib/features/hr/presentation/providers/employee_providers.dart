import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../data/models/employee.dart';
import '../../data/repositories/api_employee_repository.dart';
import '../../data/repositories/employee_repository.dart';

/// Single SWAP point. Replace the body to drop in a mock implementation.
final employeeRepositoryProvider = Provider<EmployeeRepository>((ref) {
  return ApiEmployeeRepository(dio: ref.read(dioProvider));
});

// ────────────────────────────────────────────────────────────────────
// Filter state (search + role + isActive)
// ────────────────────────────────────────────────────────────────────

class EmployeeFilter {
  final String search;
  final String? role;
  final bool? isActive;

  const EmployeeFilter({
    this.search = '',
    this.role,
    this.isActive,
  });

  EmployeeFilter copyWith({
    String? search,
    Object? role = _sentinel,
    Object? isActive = _sentinel,
  }) {
    return EmployeeFilter(
      search: search ?? this.search,
      role: identical(role, _sentinel) ? this.role : role as String?,
      isActive: identical(isActive, _sentinel)
          ? this.isActive
          : isActive as bool?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is EmployeeFilter &&
      other.search == search &&
      other.role == role &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(search, role, isActive);
}

/// Debounced filter — set with [setSearch]/[setRole]/[setActive] and the
/// list provider rebuilds 300ms after the last keystroke. Without this
/// every character would fire a request.
class EmployeeFilterController extends StateNotifier<EmployeeFilter> {
  EmployeeFilterController() : super(const EmployeeFilter());

  Timer? _debounce;
  static const _debounceDelay = Duration(milliseconds: 300);

  void setSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (mounted) state = state.copyWith(search: value);
    });
  }

  void setRole(String? role) {
    _debounce?.cancel();
    state = state.copyWith(role: role);
  }

  void setActive(bool? isActive) {
    _debounce?.cancel();
    state = state.copyWith(isActive: isActive);
  }

  void reset() {
    _debounce?.cancel();
    state = const EmployeeFilter();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final employeeFilterProvider =
    StateNotifierProvider<EmployeeFilterController, EmployeeFilter>(
  (ref) => EmployeeFilterController(),
);

// ────────────────────────────────────────────────────────────────────
// Paginated list state
// ────────────────────────────────────────────────────────────────────

/// Aggregated state for the employee list — first-page status,
/// next-page status, total count, accumulated items.
class EmployeeListState {
  final List<Employee> employees;
  final int page;
  final int total;
  final bool hasMore;

  /// True while the *first* page is being fetched (initial load or
  /// filter change). Drives the full-page shimmer.
  final bool isInitialLoading;

  /// True while a *subsequent* page is being fetched. Drives the
  /// "loading more" tile at the bottom of the list.
  final bool isLoadingMore;

  /// First-page error, if any. Renders the empty error state.
  final String? error;

  const EmployeeListState({
    this.employees = const [],
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  EmployeeListState copyWith({
    List<Employee>? employees,
    int? page,
    int? total,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
  }) {
    return EmployeeListState(
      employees: employees ?? this.employees,
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

class EmployeeListController extends StateNotifier<EmployeeListState> {
  final EmployeeRepository _repository;
  final EmployeeFilter _filter;
  static const int _pageSize = 20;

  EmployeeListController({
    required EmployeeRepository repository,
    required EmployeeFilter filter,
  })  : _repository = repository,
        _filter = filter,
        super(const EmployeeListState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(
      isInitialLoading: true,
      employees: const [],
      page: 0,
      error: null,
    );
    try {
      final pageData = await _repository.list(
        page: 1,
        pageSize: _pageSize,
        search: _filter.search.isEmpty ? null : _filter.search,
        role: _filter.role,
        isActive: _filter.isActive,
      );
      state = EmployeeListState(
        employees: pageData.employees,
        page: 1,
        total: pageData.total,
        hasMore: pageData.employees.length < pageData.total,
        isInitialLoading: false,
      );
    } on ApiError catch (e) {
      state = state.copyWith(isInitialLoading: false, error: e.message);
    } catch (e, st) {
      assert(() {
        debugPrint('employee list parse failed: $e\n$st');
        return true;
      }());
      state = state.copyWith(
        isInitialLoading: false,
        error: 'Something went wrong. Please try again.',
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
      final pageData = await _repository.list(
        page: next,
        pageSize: _pageSize,
        search: _filter.search.isEmpty ? null : _filter.search,
        role: _filter.role,
        isActive: _filter.isActive,
      );
      final combined = [...state.employees, ...pageData.employees];
      state = state.copyWith(
        employees: combined,
        page: next,
        total: pageData.total,
        hasMore: combined.length < pageData.total,
        isLoadingMore: false,
      );
    } on ApiError {
      // Keep the existing list; surface the error via snackbar at the
      // call site by re-attempting on user gesture.
      state = state.copyWith(isLoadingMore: false);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
      rethrow;
    }
  }

  /// Inserts a freshly-created employee at the top so the user sees
  /// instant feedback after the create form returns.
  void prependCreated(Employee employee) {
    state = state.copyWith(
      employees: [employee, ...state.employees],
      total: state.total + 1,
    );
  }

  /// Replaces an updated employee in place. Used by the edit screen.
  void replaceUpdated(Employee employee) {
    final idx = state.employees.indexWhere((e) => e.id == employee.id);
    if (idx == -1) return;
    final next = [...state.employees];
    next[idx] = employee;
    state = state.copyWith(employees: next);
  }

  /// Optimistic deactivate: flip locally, call server, revert on failure.
  /// Returns true on success so the caller can show the right snackbar.
  Future<bool> deactivateOptimistic(String id) async {
    final idx = state.employees.indexWhere((e) => e.id == id);
    if (idx == -1) return false;
    final original = state.employees[idx];
    final patched = original.copyWith(isActive: false);
    final next = [...state.employees];
    next[idx] = patched;
    state = state.copyWith(employees: next);

    try {
      await _repository.deactivate(id);
      // If filter excludes inactive, the next refresh will drop it.
      return true;
    } catch (_) {
      final revert = [...state.employees];
      // The list may have moved on; defensively look the row up again.
      final ridx = revert.indexWhere((e) => e.id == id);
      if (ridx != -1) {
        revert[ridx] = original;
        state = state.copyWith(employees: revert);
      }
      return false;
    }
  }
}

/// Paginated employee list driven by the current filter. autoDispose
/// to free memory when the user leaves the Employees tab.
final employeeListProvider = StateNotifierProvider.autoDispose<
    EmployeeListController, EmployeeListState>((ref) {
  final filter = ref.watch(employeeFilterProvider);
  // Keep alive across rapid filter changes for 1s — saves a refetch
  // when the user backspaces and retypes the same search quickly.
  final keepAlive = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer = Timer(const Duration(seconds: 1), keepAlive.close);
  });
  ref.onResume(() => timer?.cancel());
  return EmployeeListController(
    repository: ref.watch(employeeRepositoryProvider),
    filter: filter,
  );
});

// ────────────────────────────────────────────────────────────────────
// Single employee detail (by id)
// ────────────────────────────────────────────────────────────────────

/// Detail fetcher keyed by id. autoDispose so we don't keep stale
/// records around after the user backs out of the detail screen.
final employeeDetailProvider =
    FutureProvider.autoDispose.family<Employee, String>((ref, id) async {
  final repo = ref.watch(employeeRepositoryProvider);
  return repo.getById(id);
});

// ────────────────────────────────────────────────────────────────────
// Lightweight "all employees" provider for the Assign-KRAs picker.
// Different lifecycle from the paginated list — fetches everything in
// one go for an in-memory multi-select with client-side filtering.
// ────────────────────────────────────────────────────────────────────

final allEmployeesProvider =
    FutureProvider.autoDispose<List<Employee>>((ref) async {
  final repo = ref.watch(employeeRepositoryProvider);
  // pageSize=500 covers the realistic ceiling of an org's headcount;
  // if it ever exceeds, the picker can be upgraded to paginate.
  final page = await repo.list(page: 1, pageSize: 500, isActive: true);
  return page.employees;
});
