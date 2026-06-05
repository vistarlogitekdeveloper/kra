import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../data/models/hr_dashboard_models.dart';
import '../providers/audit_log_providers.dart';
import '../widgets/empty_state.dart';

/// Forensic trail of state-changing actions taken across the HR module.
/// Paginated reverse-chronological list backed by the audit log API.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _maybeLoadMore();
    }
  }

  Future<void> _maybeLoadMore() async {
    try {
      await ref.read(auditLogListProvider.notifier).loadMore();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.errorGeneric)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(auditLogListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.auditLogTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPurple,
        onRefresh: () => ref.read(auditLogListProvider.notifier).refresh(),
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(AuditLogListState state) {
    if (state.isInitialLoading) {
      return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        itemBuilder: (_, __) => const ListItemSkeleton(),
      );
    }

    if (state.error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: AppStrings.errorGeneric,
            message: state.error!,
            actionLabel: AppStrings.commonRetry,
            onAction: () =>
                ref.read(auditLogListProvider.notifier).refresh(),
          ),
        ],
      );
    }

    if (state.entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          EmptyState(
            icon: Icons.receipt_long_rounded,
            title: AppStrings.auditLogEmptyTitle,
            message: AppStrings.auditLogEmptyMessage,
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: state.entries.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.entries.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: ListItemSkeleton(),
          );
        }
        return _AuditTile(entry: state.entries[index]);
      },
    );
  }
}

class _AuditTile extends StatelessWidget {
  final HrActivityEntry entry;
  const _AuditTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final actor = entry.user?.name ?? '—';
    final actorCode = entry.user?.employeeCode ?? '';
    final actionLabel = _humanAction(entry.action);
    final actionColour = _colourForAction(entry.action);
    final when = DateFormat('d MMM yyyy · h:mm a').format(
      entry.createdAt.toLocal(),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: actionColour,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.entityType,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  actorCode.isEmpty ? actor : '$actor · $actorCode',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                when,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if ((entry.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.reason!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _humanAction(String raw) {
    // Backend actions look like "KRA_TEMPLATE.CREATED" — keep the verb.
    final dot = raw.lastIndexOf('.');
    final verb = dot >= 0 ? raw.substring(dot + 1) : raw;
    return verb.replaceAll('_', ' ');
  }

  Color _colourForAction(String raw) {
    final upper = raw.toUpperCase();
    if (upper.contains('DELETE') || upper.contains('REMOVE')) {
      return AppColors.error;
    }
    if (upper.contains('CREATE') || upper.contains('ADD')) {
      return AppColors.success;
    }
    if (upper.contains('UPDATE') || upper.contains('PATCH')) {
      return AppColors.accentOrange;
    }
    return AppColors.primaryPurple;
  }
}
