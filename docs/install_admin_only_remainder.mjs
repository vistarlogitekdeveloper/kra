/**
 * ADMIN_ONLY: management rates the KRAs HR and Accounts were not assigned.
 *
 *     node D:\Vistar\krafrontend\docs\install_admin_only_remainder.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_admin_only_remainder.mjs
 *
 * Idempotent; all-or-nothing; backs each file up as <name>.bak before writing.
 * `--kra=<dir>` patches a COPY of the dist tree so the result can be
 * syntax-checked before the deployed files are touched.
 *
 * RUN docs/install_rating_roles.mjs FIRST — this leans on the canActOnStage
 * helper that script introduces. Preflight refuses to run without it.
 *
 * ── THE RULE ────────────────────────────────────────────────────────────────
 *
 *   HR rates the KRAs assigned to HR.
 *   Accounts rates the KRAs assigned to Accounts.
 *   MANAGEMENT rates everything left over — the KRAs pointing at the reporting
 *   manager, and any with no assignment at all.
 *   Management then signs off the quarter as before.
 *
 * Only the employee's SELF_RATING is removed by this flow.
 *
 * ── WHY THE REPORTING_MANAGER_RATING STAGE IS KEPT ──────────────────────────
 *
 * It is REASSIGNED, not deleted. Deleting it left every manager-assigned KRA —
 * and every never-assigned KRA, because monthly rows default to that seat —
 * with no eligible rater at all. Worse, those rows then vanished from the
 * weighted totals rather than scoring zero, so a 20%-weighted KRA nobody could
 * rate silently redistributed its weight across the others and the sheet still
 * printed a plausible percentage.
 *
 * Keeping the stage means every KRA still resolves a Review score through its
 * own assigned stage, the weighting stays honest, and — critically — the
 * per-KRA reviewer guard in writeRowScores needs NO change: it already maps a
 * MANAGER reviewer_group to REPORTING_MANAGER_RATING, so a management write to
 * that stage matches and is stored. A remap to some other stage would have been
 * silently discarded by that same guard.
 *
 * ── WHAT CHANGES ────────────────────────────────────────────────────────────
 *
 *  1. repository: organizationReviewFlow(organizationId) — reads
 *     kra.organizations.review_flow over raw SQL (no Prisma field needed, so it
 *     cannot break on a client that has not been regenerated), memoized for a
 *     few seconds because saveScores hits it on every keystroke-sized write.
 *
 *  2. assertCanAct becomes async and asks the flow before deciding whether
 *     REPORTING_MANAGER_RATING is a relationship or a role. It has exactly one
 *     caller, so this is safe.
 *
 *  3. saveScores does the same for its own REPORTING_MANAGER_RATING branch.
 *
 *  4. The manager ceiling is SKIPPED under ADMIN_ONLY, in both paths. This is
 *     not a nicety — assertManagerCeiling rejects any row with no self score
 *     ("The employee has not self-rated this KRA yet."), and under a flow with
 *     no self-rating that is EVERY row. Left in place it would refuse every
 *     management write with a 400 while the role checks all passed.
 *
 *  5. assertNotSelfManaged is skipped under ADMIN_ONLY. It exists so nobody
 *     signs off their own manager rating via a self-referential manager_id;
 *     once the seat is held by a role rather than by the reporting manager, the
 *     relationship is irrelevant and the check would only strand a
 *     self-managed employee's whole sheet.
 *
 *  6. `approved: false` on REPORTING_MANAGER_RATING is refused under
 *     ADMIN_ONLY. It hands the review back to SELF_RATING — a stage this flow
 *     grants to nobody — which would park it where no actor can move it on.
 *
 * ── WHAT DELIBERATELY DOES *NOT* CHANGE ─────────────────────────────────────
 *
 *   * The STANDARD pipeline. Every edit below is inside an
 *     `if (flow === 'ADMIN_ONLY')` branch whose else-path is the original code,
 *     byte for byte. An organisation on the standard flow runs what it ran.
 *   * SELF_RATING stays owner-only in every flow.
 *   * writeRowScores and its SQL guard are untouched.
 *   * No route guards change.
 */
import fs from 'fs';

const kraArg = process.argv.find((a) => a.startsWith('--kra='));
const KRA = kraArg
  ? kraArg.slice('--kra='.length)
  : 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const SVC = `${KRA}/features/monthly-reviews/monthly-reviews.service.js`;
const REPO = `${KRA}/features/monthly-reviews/monthly-reviews.repository.js`;
const DRY = process.argv.includes('--dry');

const EDITS = [
  // ── 1. repository: the flow lookup ─────────────────────────────────────
  {
    file: REPO,
    marker: 'async organizationReviewFlow(organizationId)',
    find: `exports.monthlyReviewsRepository = {`,
    replace: [
      '// Which review pipeline an organization runs. Read over raw SQL rather',
      '// than through the Prisma client on purpose: the column is reachable the',
      '// moment the migration has run, with no dependency on `prisma generate`',
      '// having been re-run — the same reason reviewer_group and the proof',
      '// columns are handled this way.',
      '//',
      '// Memoized for a few seconds. saveScores consults it on every per-row',
      '// write and the value effectively never changes, so a per-write round',
      "// trip would be pure overhead. A stale read can only mean an operator's",
      '// flow change takes a moment to apply, never a wrong answer that sticks.',
      'const _flowCache = new Map(); // organizationId -> { flow, at }',
      'const FLOW_TTL_MS = 5000;',
      '',
      'exports.monthlyReviewsRepository = {',
      '    // Returns "STANDARD" or "ADMIN_ONLY". Falls back to "STANDARD" for an',
      '    // unknown organization, a null id, or any read failure: defaulting to',
      '    // the original pipeline is the only safe direction, because guessing',
      '    // ADMIN_ONLY would strip a live tenant of its self-rating.',
      '    async organizationReviewFlow(organizationId) {',
      '        if (!organizationId)',
      "            return 'STANDARD';",
      '        const hit = _flowCache.get(organizationId);',
      '        if (hit && Date.now() - hit.at < FLOW_TTL_MS)',
      '            return hit.flow;',
      '        let flow = \'STANDARD\';',
      '        try {',
      '            const rows = await database_1.prisma.$queryRawUnsafe(`SELECT review_flow FROM kra.organizations WHERE id = $1`, organizationId);',
      "            const raw = rows && rows[0] ? rows[0].review_flow : null;",
      "            if (typeof raw === 'string' && raw.trim().toUpperCase() === 'ADMIN_ONLY')",
      "                flow = 'ADMIN_ONLY';",
      '        }',
      '        catch {',
      '            // Column not migrated yet, or the read failed. STANDARD.',
      '        }',
      '        _flowCache.set(organizationId, { flow, at: Date.now() });',
      '        return flow;',
      '    },',
    ].join('\n'),
  },

  // ── 2. assertCanAct: async + flow-aware ────────────────────────────────
  {
    file: SVC,
    marker: 'async function assertCanAct(user, header, stage)',
    find: `function assertCanAct(user, header, stage) {`,
    replace: `async function assertCanAct(user, header, stage) {`,
  },
  {
    file: SVC,
    marker: `// ADMIN_ONLY: this seat belongs to MANAGEMENT as a ROLE`,
    find: `    if (stage === 'REPORTING_MANAGER_RATING') {
        assertNotSelfManaged(header);
        // Fails closed when the employee has no manager (manager_id null).
        if (!header.manager_id || header.manager_id !== user.id) {
            throw new http_errors_1.ForbiddenError('Only the reporting manager can rate this review.');
        }
        return;
    }`,
    replace: `    if (stage === 'REPORTING_MANAGER_RATING') {
        // ADMIN_ONLY: this seat belongs to MANAGEMENT as a ROLE, not to the
        // employee's reporting manager as a relationship. HR and Accounts rate
        // the KRAs assigned to them; management rates the remainder. Asking the
        // relationship here would refuse the only people the flow grants it to.
        const flow = await monthly_reviews_repository_1.monthlyReviewsRepository.organizationReviewFlow(header.organization_id);
        if (flow === 'ADMIN_ONLY') {
            if (!canActOnStage(user, 'MANAGEMENT_REVIEW')) {
                throw new http_errors_1.ForbiddenError(\`Role \${user.role} cannot rate the remaining KRAs.\`);
            }
            return;
        }
        assertNotSelfManaged(header);
        // Fails closed when the employee has no manager (manager_id null).
        if (!header.manager_id || header.manager_id !== user.id) {
            throw new http_errors_1.ForbiddenError('Only the reporting manager can rate this review.');
        }
        return;
    }`,
  },

  // ── 3. submitStage: await, skip the ceiling, refuse the hand-back ──────
  {
    file: SVC,
    marker: `        await assertCanAct(user, header, stage);`,
    find: `        assertCanAct(user, header, stage);
        // Change 3 — a reporting manager's per-KRA score may not exceed the
        // employee's own. Enforced before any write (submit path).
        if (stage === 'REPORTING_MANAGER_RATING' && body.rowScores)
            await assertManagerCeiling(id, body.rowScores);`,
    replace: `        await assertCanAct(user, header, stage);
        const submitFlow = await monthly_reviews_repository_1.monthlyReviewsRepository.organizationReviewFlow(header.organization_id);
        // Change 3 — a reporting manager's per-KRA score may not exceed the
        // employee's own. Enforced before any write (submit path).
        //
        // SKIPPED under ADMIN_ONLY, and not as a convenience: the ceiling
        // rejects any row with no self score at all, and that flow has no
        // self-rating, so every row qualifies. Left in, it would refuse every
        // management write with a 400 after all the role checks had passed.
        if (stage === 'REPORTING_MANAGER_RATING'
            && body.rowScores
            && submitFlow !== 'ADMIN_ONLY')
            await assertManagerCeiling(id, body.rowScores);
        // Handing the work back one step means "employee, revise your
        // self-rating". Under ADMIN_ONLY that stage admits nobody, so the
        // review would be parked where no actor can move it on.
        if (stage === 'REPORTING_MANAGER_RATING'
            && body.approved === false
            && submitFlow === 'ADMIN_ONLY') {
            throw new http_errors_1.ConflictError('This organization has no self-rating to send back to.');
        }`,
  },

  // ── 4. saveScores: flow-aware seat + skip the ceiling ──────────────────
  {
    file: SVC,
    marker: `// ADMIN_ONLY hands this seat to MANAGEMENT`,
    find: `        else if (stage === 'REPORTING_MANAGER_RATING') {
            assertNotSelfManaged(header);
            if (!header.manager_id || header.manager_id !== user.id)
                throw new http_errors_1.ForbiddenError('Only the reporting manager can edit manager scores.');
        }`,
    replace: `        else if (stage === 'REPORTING_MANAGER_RATING') {
            // ADMIN_ONLY hands this seat to MANAGEMENT as a role — the KRAs HR
            // and Accounts were not assigned. See assertCanAct.
            if (saveFlow === 'ADMIN_ONLY') {
                if (!canActOnStage(user, 'MANAGEMENT_REVIEW'))
                    throw new http_errors_1.ForbiddenError(\`Role \${user.role} cannot rate the remaining KRAs.\`);
            }
            else {
                assertNotSelfManaged(header);
                if (!header.manager_id || header.manager_id !== user.id)
                    throw new http_errors_1.ForbiddenError('Only the reporting manager can edit manager scores.');
            }
        }`,
  },
  {
    file: SVC,
    marker: `        const saveFlow = await monthly_reviews_repository_1.monthlyReviewsRepository.organizationReviewFlow(header.organization_id);`,
    find: `        const stage = body.stage;
        // Once management has locked the review, its management scores are fixed`,
    replace: `        const stage = body.stage;
        const saveFlow = await monthly_reviews_repository_1.monthlyReviewsRepository.organizationReviewFlow(header.organization_id);
        // Once management has locked the review, its management scores are fixed`,
  },
  {
    file: SVC,
    marker: `        if (stage === 'REPORTING_MANAGER_RATING' && saveFlow !== 'ADMIN_ONLY')`,
    find: `        if (stage === 'REPORTING_MANAGER_RATING')
            await assertManagerCeiling(id, body.rowScores || {});`,
    replace: `        // Skipped under ADMIN_ONLY — see submitStage: with no self-rating in
        // the flow, the ceiling rejects every row.
        if (stage === 'REPORTING_MANAGER_RATING' && saveFlow !== 'ADMIN_ONLY')
            await assertManagerCeiling(id, body.rowScores || {});`,
  },
];

// ── Preflight ───────────────────────────────────────────────────────────────
for (const f of [SVC, REPO]) {
  if (!fs.existsSync(f)) {
    console.error(`FAIL  not found: ${f}`);
    process.exit(1);
  }
}
const svcPre = fs.readFileSync(SVC, 'utf8');
if (!svcPre.includes('function canActOnStage(user, stage)')) {
  console.error('FAIL  canActOnStage is not in monthly-reviews.service.js.');
  console.error('      Run docs/install_rating_roles.mjs FIRST — this patch');
  console.error('      gates the management seat through that helper, which also');
  console.error('      resolves SUPER_ADMIN via the rbac role hierarchy.');
  process.exit(1);
}
if (!svcPre.includes("MANAGEMENT_REVIEW: ['ADMIN', 'HR_ADMIN', 'MANAGEMENT']")) {
  console.error('FAIL  ACTOR_ROLES.MANAGEMENT_REVIEW does not list MANAGEMENT.');
  console.error('      Run docs/install_rating_roles.mjs FIRST, or management');
  console.error('      would be refused on the very seat this patch grants it.');
  process.exit(1);
}
console.log('  PRE    canActOnStage + MANAGEMENT present — install_rating_roles applied');

// ── Apply ───────────────────────────────────────────────────────────────────
const byFile = new Map();
for (const f of [SVC, REPO]) byFile.set(f, fs.readFileSync(f, 'utf8'));

let applied = 0;
let skipped = 0;
let failed = 0;

for (const e of EDITS) {
  const name = e.file.split('/').pop();
  const label = `${name}: ${e.marker.split('\n')[0].trim().slice(0, 46)}`;
  let src = byFile.get(e.file);
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const N = (t) => t.split('\n').join(eol);

  if (src.includes(N(e.marker))) {
    console.log(`  SKIP   ${label} — already present`);
    skipped++;
    continue;
  }

  const find = N(e.find);
  const hits = src.split(find).length - 1;
  if (hits !== 1) {
    console.error(`  FAIL   ${label} — anchor matched ${hits} times, expected 1`);
    failed++;
    continue;
  }

  byFile.set(e.file, src.replace(find, N(e.replace)));
  console.log(`  ${DRY ? 'WOULD ' : 'OK    '} ${label}`);
  applied++;
}

if (failed > 0) {
  console.error('');
  console.error(`FAILED — ${failed} anchor(s) did not match. NOTHING was written.`);
  console.error('Half of this patch is worse than none: the flow lookup and the');
  console.error('branches that use it have to land together.');
  process.exit(1);
}

console.log('');
if (DRY) {
  console.log(`dry run: ${applied} would apply, ${skipped} already done`);
  process.exit(0);
}

if (applied === 0) {
  console.log(`nothing to do (skipped=${skipped}) — already patched`);
  process.exit(0);
}

for (const [f, src] of byFile) {
  fs.copyFileSync(f, `${f}.bak`);
  fs.writeFileSync(f, src, 'utf8');
}
console.log(`applied=${applied} skipped=${skipped}`);
console.log('');
console.log('Next: restart / redeploy the API.');
console.log('');
console.log('Verify — on an ADMIN_ONLY organization, as a MANAGEMENT user:');
console.log('  open a sheet with a KRA assigned to the Reporting Manager');
console.log('  the Review cell should read "Rate +", not a pending chip');
console.log('  enter a score -> 200, and it survives a refresh');
console.log('Verify the STANDARD flow did not move:');
console.log('  on a STANDARD org, a MANAGEMENT user must still be refused that');
console.log('  seat, and the employee\'s own manager must still hold it');
for (const f of byFile.keys()) {
  const n = f.split('/').pop();
  console.log(`  restore: copy ${n}.bak ${n}`);
}
