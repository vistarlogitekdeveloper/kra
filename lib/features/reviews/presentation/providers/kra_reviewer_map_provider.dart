import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/kra_reviewer.dart';
import '../../../hr/presentation/providers/kra_assignment_providers.dart';
import '../../../hr/presentation/providers/kra_template_providers.dart';

/// Per-KRA reviewer assignment for an employee, resolved from the template.
///
/// [byName] maps a NORMALISED KRA name (see [kraNameKey]) → its single reviewer,
/// and [byOrder] lists reviewers in template sort order. The sheet matches a
/// review row on name first, then falls back to its position — two independent
/// keys so an exact-name mismatch (stray spaces, punctuation, a renamed item)
/// no longer drops the assignment.
typedef KraReviewerAssignment = ({
  Map<String, KraReviewer> byName,
  List<KraReviewer?> byOrder,
});

/// Canonical key for matching a KRA by name across the template and the
/// generated review row: lower-cased with every non-alphanumeric character
/// stripped, so "HR compliances", "HR Compliances " and "HR-compliances" all
/// collapse to the same key.
String kraNameKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Per-KRA reviewer assignment for an employee.
///
/// Each KRA is assigned to ONE reviewer (Reporting Manager / HR / Accounts). HR
/// sets that on the TEMPLATE (its `score_source`); it also rides on the
/// employee's assignment items. The monthly-review row snapshots it too — but
/// only ONCE, at generation, and never retroactively — so a row generated
/// BEFORE the reviewer was set carries a stale/default value. This provider
/// therefore reads the CURRENT assignment (its items first, then its source
/// template, which is where the reviewer really lives) so the sheet can treat
/// it as authoritative over the stale snapshot. Best-effort: empty on failure
/// (the sheet then keeps the row's own value / defaults to the reporting
/// manager).
final kraReviewerMapProvider = FutureProvider.autoDispose
    .family<KraReviewerAssignment, String>((ref, employeeId) async {
  const empty = (
    byName: <String, KraReviewer>{},
    byOrder: <KraReviewer?>[],
  );
  if (employeeId.isEmpty) return empty;
  try {
    final assignments = await ref
        .read(kraAssignmentRepositoryProvider)
        .list(employeeId: employeeId);
    if (assignments.isEmpty) return empty;
    // Prefer an assignment that actually carries items and/or a template.
    final chosen = assignments.firstWhere(
      (a) => a.items.isNotEmpty || (a.templateId?.isNotEmpty ?? false),
      orElse: () => assignments.first,
    );

    final byName = <String, KraReviewer>{};
    final byOrder = <KraReviewer?>[];

    // 1) From the assignment's own items, in order. Carries the reviewer when
    //    it was written per-assignment; otherwise just seeds names/positions.
    final items = [...chosen.items]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final item in items) {
      final r = item.reviewerGroup;
      if (r != null) byName[kraNameKey(item.name)] = r;
      byOrder.add(r);
    }

    // 2) Merge the SOURCE template's items — the canonical place the reviewer
    //    is set. Template wins for name matches and fills any positional gaps.
    final templateId = chosen.templateId;
    if (templateId != null && templateId.isNotEmpty) {
      try {
        final template =
            await ref.read(kraTemplateRepositoryProvider).getById(templateId);
        final tItems = [...template.items]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        for (var i = 0; i < tItems.length; i++) {
          final r = tItems[i].reviewerGroup;
          if (r == null) continue;
          byName[kraNameKey(tItems[i].name)] = r;
          if (i < byOrder.length) {
            byOrder[i] = byOrder[i] ?? r;
          } else {
            byOrder.add(r);
          }
        }
      } catch (_) {
        // Template fetch failed — keep whatever the assignment gave us.
      }
    }

    return (byName: byName, byOrder: byOrder);
  } catch (_) {
    return empty;
  }
});
