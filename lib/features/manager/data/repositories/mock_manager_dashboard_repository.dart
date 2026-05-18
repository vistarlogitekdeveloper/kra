import '../models/manager_dashboard.dart';
import '../models/manager_stats.dart';
import '../models/pending_action.dart';
import 'manager_dashboard_repository.dart';

/// In-memory fake for the manager dashboard. Returns a realistic
/// Amol-Veer-as-team-lead scenario so the UI can be developed and
/// demoed without a live backend.
///
/// Swap in via the provider's body (see `manager_dashboard_providers.dart`).
class MockManagerDashboardRepository implements ManagerDashboardRepository {
  /// Artificial latency so shimmer skeletons get to render — set to
  /// `Duration.zero` in tests to keep them snappy.
  final Duration latency;

  const MockManagerDashboardRepository({
    this.latency = const Duration(milliseconds: 350),
  });

  @override
  Future<ManagerDashboard> fetchDashboard() async {
    await Future<void>.delayed(latency);
    final now = DateTime.now();
    return ManagerDashboard(
      manager: const ManagerCardUser(
        id: 'mgr-001',
        name: 'Amol Veer',
        employeeCode: 'VLPL0042',
        role: 'MANAGER',
        grade: 'M2',
        projectLocation: 'Pune HQ',
      ),
      activeCycle: ManagerActiveCycle(
        id: 'cycle-q1-fy27',
        name: 'Q1 FY 2026-27',
        status: 'ACTIVE',
        fyLabel: 'FY 2026-27',
        quarterNum: 1,
        endDate: now.add(const Duration(days: 28)),
        managerReviewDeadline: now.add(const Duration(days: 5)),
        deadlineRemaining: 5,
      ),
      stats: const ManagerStats(
        totalReports: 5,
        pendingMyReview: 1,
        completedThisMonth: 2,
        overdueReviews: 0,
      ),
      pendingActions: [
        PendingAction(
          reviewId: 'rev-vikram-q1',
          employeeId: 'emp-vikram',
          employeeName: 'Vikram Sinha',
          employeeCode: 'VLPL0210',
          monthLabel: 'Apr 2026',
          submittedAt: now.subtract(const Duration(days: 2)),
          deadlineRemaining: 5,
        ),
      ],
      lastCycleTrend: const TeamTrend(
        cycleId: 'cycle-q4-fy26',
        cycleName: 'Q4 FY 2025-26',
        averageScore: 78.4,
        highest: TopPerformer(
          employeeId: 'emp-sagar',
          name: 'Sagar Patil',
          score: 92.0,
        ),
        lowest: TopPerformer(
          employeeId: 'emp-neha',
          name: 'Neha Kulkarni',
          score: 63.5,
        ),
        completionRate: 1.0,
      ),
    );
  }
}
