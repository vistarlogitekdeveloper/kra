/**
 * My Team is the REPORTING-LINE view, whatever the caller's role.
 *
 *     node D:\Vistar\krafrontend\docs\install_my_team_reporting_line.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_my_team_reporting_line.mjs
 *
 * Idempotent; all-or-nothing; backs the file up as <name>.bak before writing.
 * `--kra=<dir>` patches a COPY of the dist tree so the result can be
 * syntax-checked before the deployed file is touched.
 *
 * ── WHY ─────────────────────────────────────────────────────────────────────
 *
 * Reported: on My Team, a manager sees people who do not report to them, and
 * can rate them.
 *
 * `listTeam` (GET /manager/team) was ALREADY scoped to `managerId: actor.id`
 * for every role — its own comment records that as a deliberate change:
 * "Previously HR_ADMIN (and, by extension, any senior tier) was exempted from
 * the managerId filter and so saw the whole org; scope by reporting line for
 * ALL roles."
 *
 * Every OTHER gate in the module kept the HR_ADMIN exemption. So the dashboard
 * beside that list was org-wide, and `countDirectReports` — which IS scoped —
 * sat next to it: a `totalReports` of 3 above a pending-actions list of forty.
 *
 * Worse, the rule was implemented EIGHT times: four calls to
 * `ensureManagerOf`, and four inline restatements of
 * `actor.role !== 'HR_ADMIN' && x.managerId !== actor.id`. That is the drift
 * CLAUDE.md B1 forbids — "derive gates from the model; never restate".
 *
 * ── WHAT CHANGES ────────────────────────────────────────────────────────────
 *
 * One predicate, `leads(actor, managerId)`, owns the rule. Every visibility and
 * rating gate calls it:
 *
 *   ensureManagerOf              (4 call sites: rate, detail, submit, history)
 *   buildReviewWhereForManager   (getDashboard stats + pendingActions,
 *                                 teamPerformance)
 *   getTeamMember                (inline → leads)
 *   getTeamHistory               (inline → leads)
 *   review permissions canRate / canEdit  (inline → leads)
 *   bulkApprove                  (inline → leads)
 *
 * ── WHAT DELIBERATELY DOES *NOT* CHANGE ─────────────────────────────────────
 *
 *   * The managerReviewDeadline overrides (three `actor.role !== 'HR_ADMIN'`
 *     checks further down). Letting HR act AFTER a deadline is a different
 *     policy from letting HR SEE another manager's team. Narrowing those would
 *     be an unrequested behaviour regression, so they stay. The script asserts
 *     afterwards that exactly those three remain.
 *   * The HR Admin workspace. It reaches org-wide data through /employees and
 *     /reviews, NOT through /manager/* — verified by grepping the Flutter
 *     client for every ApiConstants.managerTeam / managerDashboard /
 *     managerReviews caller: all of them live in lib/features/manager/.
 *   * GET /reviews/monthly (`scopeFilters`). That is the REVIEWER surface, and
 *     its org-wide default for HR_ADMIN / FINANCE / HR is load-bearing: under
 *     ADMIN_ONLY, Accounts rates the Accounts KRA and HR the HR KRA across the
 *     ORGANISATION. A FINANCE user typically has zero direct reports, so
 *     scoping that endpoint by reporting line would leave the Accounts seat
 *     unable to rate anyone. Explicitly out of scope, by decision.
 *   * `/reviews/:id/scores` (the manager auto-save). Its HR override is
 *     audit-logged on purpose ("HR override: ... outside of normal flow") and
 *     the endpoint is shared with the Reviews workspace.
 *
 * ── A NULL REPORTING MANAGER ────────────────────────────────────────────────
 *
 * `leads` treats a null managerId as NOT a match, so an employee with no
 * reporting manager is invisible on My Team rather than visible to everybody.
 * That matches `listTeam`'s `managerId: actor.id`, which already excluded them.
 * HR still reaches them through the HR Admin workspace.
 */
import fs from 'fs';

const kraArg = process.argv.find((a) => a.startsWith('--kra='));
const KRA = kraArg
  ? kraArg.slice('--kra='.length)
  : 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const SVC = `${KRA}/features/manager/manager.service.js`;
const DRY = process.argv.includes('--dry');

const EDITS = [
  // ── 1. the single predicate, and the helper that already existed ─────────
  {
    id: 'leads-predicate',
    marker: 'function leads(actor, managerId) {',
    find: [
      'function ensureManagerOf(review, actor) {',
      "    if (actor.role === 'HR_ADMIN') return;",
      '    if (review.managerId !== actor.id) {',
      "        throw new http_errors_1.ForbiddenError('NOT_YOUR_REPORT');",
      '    }',
      '}',
    ].join('\n'),
    replace: [
      '// Does `actor` lead the person this row belongs to?',
      '//',
      '// THE single source of truth for the My Team workspace, which is the',
      "// REPORTING-LINE view whatever the caller's role — `employees.manager_id`",
      '// is the only thing that decides it (see the note above).',
      '//',
      '// Deliberately role-BLIND. HR_ADMIN used to be exempt at every gate below,',
      '// which made getDashboard org-wide while listTeam beside it was already',
      '// scoped for all roles: the pending-actions list showed the whole company',
      '// next to a `totalReports` of three. HR keeps its org-wide powers in the HR',
      '// Admin workspace (/employees, /reviews), which does not route through this',
      '// module at all.',
      '//',
      '// VISIBILITY only. The managerReviewDeadline overrides further down still',
      '// honour HR_ADMIN: letting HR act AFTER a deadline is a different policy',
      "// from letting HR see another manager's team.",
      '//',
      '// A null managerId is NOT a match, so an employee with no reporting manager',
      '// is invisible here rather than visible to everyone. That matches listTeam.',
      'function leads(actor, managerId) {',
      '    return managerId != null && managerId === actor.id;',
      '}',
      '',
      'function ensureManagerOf(review, actor) {',
      '    if (!leads(actor, review.managerId)) {',
      "        throw new http_errors_1.ForbiddenError('NOT_YOUR_REPORT');",
      '    }',
      '}',
    ].join('\n'),
  },

  // ── 2. the stale header note ─────────────────────────────────────────────
  {
    id: 'header-note',
    marker: '//                                for EVERY role — see `leads`',
    find: [
      '//   * getDashboard / listTeam  → queries filtered to `managerId: actor.id`',
      '//                                (HR_ADMIN stays org-wide)',
    ].join('\n'),
    replace: [
      '//   * getDashboard / listTeam  → queries filtered to `managerId: actor.id`',
      '//                                for EVERY role — see `leads`',
    ].join('\n'),
  },

  // ── 3. the dashboard's review set ────────────────────────────────────────
  {
    id: 'dashboard-where',
    marker: '        // Last, so no extraWhere from a caller can widen the scope.',
    find: [
      'function buildReviewWhereForManager(actor, cycleId, extraWhere = {}) {',
      '    // HR_ADMIN sees everyone; MANAGER sees only their direct reports.',
      '    const where = {',
      '        reviewCycle: { organizationId: actor.organizationId },',
      '        ...(cycleId ? { reviewCycleId: cycleId } : {}),',
      '        ...extraWhere,',
      '    };',
      "    if (actor.role !== 'HR_ADMIN') {",
      '        where.managerId = actor.id;',
      '    }',
      '    return where;',
      '}',
    ].join('\n'),
    replace: [
      'function buildReviewWhereForManager(actor, cycleId, extraWhere = {}) {',
      '    // Reporting line for EVERY role — see `leads`. Drives getDashboard\'s',
      '    // stats and pendingActions, and teamPerformance from the prior cycle.',
      '    // `countDirectReports` beside it was ALREADY scoped, so exempting',
      '    // HR_ADMIN here produced a dashboard whose list and whose count',
      '    // disagreed with each other.',
      '    return {',
      '        reviewCycle: { organizationId: actor.organizationId },',
      '        ...(cycleId ? { reviewCycleId: cycleId } : {}),',
      '        ...extraWhere,',
      '        // Last, so no extraWhere from a caller can widen the scope.',
      '        managerId: actor.id,',
      '    };',
      '}',
    ].join('\n'),
  },

  // ── 4. getTeamMember AND getTeamHistory — byte-identical gates ───────────
  {
    id: 'employee-gates',
    marker: '        if (!leads(actor, employee.managerId)) {',
    find: "        if (actor.role !== 'HR_ADMIN' && employee.managerId !== actor.id) {",
    replace: '        if (!leads(actor, employee.managerId)) {',
    // Two call sites (getTeamMember, getTeamHistory) with identical text and
    // identical intent, so both are rewritten in one pass rather than
    // disambiguated by surrounding context.
    expectHits: 2,
  },

  // ── 5. the permissions the CLIENT renders an editable matrix from ────────
  {
    id: 'rate-permissions',
    marker: '                // `leads`, not a role check: the client renders an',
    find: [
      '            permissions: {',
      '                canRate:',
      '                    !deadlinePassed &&',
      '                    editableStates.includes(review.state) &&',
      "                    (actor.role === 'HR_ADMIN' || review.managerId === actor.id),",
      '                canEdit:',
      "                    review.state === 'MANAGER_RATED_ALL' &&",
      '                    !deadlinePassed &&',
      "                    (actor.role === 'HR_ADMIN' || review.managerId === actor.id),",
    ].join('\n'),
    replace: [
      '            permissions: {',
      '                // `leads`, not a role check: the client renders an',
      '                // EDITABLE matrix off canRate, so an HR_ADMIN opening a',
      "                // non-report's review through My Team was handed a",
      '                // working rating form.',
      '                canRate:',
      '                    !deadlinePassed &&',
      '                    editableStates.includes(review.state) &&',
      '                    leads(actor, review.managerId),',
      '                canEdit:',
      "                    review.state === 'MANAGER_RATED_ALL' &&",
      '                    !deadlinePassed &&',
      '                    leads(actor, review.managerId),',
    ].join('\n'),
  },

  // ── 6. bulk approve ──────────────────────────────────────────────────────
  {
    id: 'bulk-approve',
    marker: '            // `leads` — bulk approve SKIPS a non-report',
    find: [
      "            if (actor.role !== 'HR_ADMIN' && review.managerId !== actor.id) {",
      "                skipped.push({ reviewId, employeeName: review.employee.name, reason: 'NOT_YOUR_REPORT' });",
    ].join('\n'),
    replace: [
      '            // `leads` — bulk approve SKIPS a non-report rather than',
      '            // throwing, so one foreign id in the batch does not fail the',
      '            // whole request.',
      '            if (!leads(actor, review.managerId)) {',
      "                skipped.push({ reviewId, employeeName: review.employee.name, reason: 'NOT_YOUR_REPORT' });",
    ].join('\n'),
  },
];

if (!fs.existsSync(SVC)) {
  console.error(`FAIL  not found: ${SVC}`);
  process.exit(1);
}

let src = fs.readFileSync(SVC, 'utf8');
const eol = src.includes('\r\n') ? '\r\n' : '\n';
const N = (t) => t.split('\n').join(eol);

let applied = 0;
let skipped = 0;
let failed = 0;

for (const e of EDITS) {
  if (src.includes(N(e.marker))) {
    console.log(`  SKIP   ${e.id} — already present`);
    skipped++;
    continue;
  }
  const find = N(e.find);
  const want = e.expectHits ?? 1;
  const hits = src.split(find).length - 1;
  if (hits !== want) {
    console.error(`  FAIL   ${e.id} — anchor matched ${hits} times, expected ${want}`);
    failed++;
    continue;
  }
  src = src.split(find).join(N(e.replace));
  console.log(`  ${DRY ? 'WOULD ' : 'OK    '} ${e.id}${want > 1 ? ` (x${want})` : ''}`);
  applied++;
}

if (failed > 0) {
  console.error('');
  console.error(`FAILED — ${failed} anchor(s) did not match. NOTHING was written.`);
  console.error('Half-applying this leaves some gates role-based and some');
  console.error('relationship-based, which is the drift the change exists to remove.');
  process.exit(1);
}

// ── Post-check: only the DEADLINE overrides may still mention HR_ADMIN ─────
const residual = src
  .split(eol)
  .map((line, i) => ({ n: i + 1, line }))
  .filter((r) => r.line.includes('HR_ADMIN') && !r.line.trimStart().startsWith('//'));

console.log('');
console.log('Residual HR_ADMIN checks (expected: exactly 3 deadline overrides):');
for (const r of residual) console.log(`  ${r.n}: ${r.line.trim()}`);

const nonDeadline = residual.filter((r) => !r.line.includes('getTime() < Date.now()'));
if (nonDeadline.length > 0) {
  console.error('');
  console.error('FAILED — a non-deadline HR_ADMIN check survived:');
  for (const r of nonDeadline) console.error(`  ${r.n}: ${r.line.trim()}`);
  console.error('Every visibility/rating gate was supposed to route through `leads`.');
  process.exit(1);
}
if (residual.length !== 3) {
  console.error('');
  console.error(`FAILED — expected 3 deadline overrides, found ${residual.length}.`);
  console.error('The file has changed shape; re-read it before trusting this patch.');
  process.exit(1);
}
console.log('  ✓ all three are deadline overrides, deliberately kept');

console.log('');
if (DRY) {
  console.log(`dry run: ${applied} would apply, ${skipped} already done`);
  process.exit(0);
}
if (applied === 0) {
  console.log(`nothing to do (skipped=${skipped}) — already patched`);
  process.exit(0);
}

fs.copyFileSync(SVC, `${SVC}.bak`);
fs.writeFileSync(SVC, src, 'utf8');
console.log(`applied=${applied} skipped=${skipped}`);
console.log('');
console.log('Syntax-check, then commit + push (Render redeploys on push):');
console.log(`  node --check ${SVC}`);
console.log('');
console.log('Verify as a MANAGER-ish user who leads nobody:');
console.log('  GET /manager/dashboard  -> stats.totalReports 0, pendingActions []');
console.log('  GET /manager/team       -> []');
console.log('Verify as an HR_ADMIN who leads 2 people:');
console.log('  GET /manager/team       -> exactly those 2');
console.log('  GET /manager/dashboard  -> pendingActions only for those 2,');
console.log('                             and totalReports 2 (list and count AGREE)');
console.log('  GET /reviews/monthly    -> still ORG-WIDE (reviewer surface, unchanged)');
console.log('');
console.log(`  restore: copy manager.service.js.bak manager.service.js`);
