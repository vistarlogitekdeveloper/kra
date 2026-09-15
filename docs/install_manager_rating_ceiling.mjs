/**
 * A manager may not score ABOVE the employee's own self-rating.
 *
 *     node D:\Vistar\krafrontend\docs\install_manager_rating_ceiling.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_manager_rating_ceiling.mjs
 *
 * Idempotent; backs the file up as <name>.bak. `--kra=<dir>` patches a COPY.
 *
 * ── WHY ─────────────────────────────────────────────────────────────────────
 *
 * Reported: an employee self-rated 90 and the manager was able to enter more
 * than 90. The manager's job is to moderate the employee's number, so the
 * self-rating is the ceiling.
 *
 * ── WHERE ───────────────────────────────────────────────────────────────────
 *
 * `reviewsService.updateScores` — ONE place, and it covers all three manager
 * write paths. Verified, not assumed:
 *
 *   POST /reviews/:id/scores            the matrix auto-save (where the number
 *                                       is actually typed)
 *   POST /manager/reviews/:id/manager-rate    → delegates here
 *   PATCH /manager/reviews/:id/manager-rate   → delegates here
 *
 * `submitManagerRate` says so itself: "Delegate score upserts to the existing
 * reviews service — single source of truth for cell-level validation (max
 * score, locked months, row source)". Neither manager-rate handler validates a
 * score on its own, so putting the ceiling anywhere else would leave two of
 * the three doors open.
 *
 * The guard sits inside the existing `newRating != null` block, immediately
 * after the max-score check, so it reuses the value that block already
 * resolved rather than re-deriving which side is being written.
 *
 * ── THE CASE THAT MUST NOT BREAK ────────────────────────────────────────────
 *
 * An ABSENT self-rating is NO ceiling, not a ceiling of zero.
 *
 * Under ADMIN_ONLY there is no self-rating stage at all — HR rates the HR KRA,
 * Accounts the Accounts KRA, management the remainder, and no employee ever
 * enters a number. Treating a null self as 0 would refuse every one of those
 * writes and take the whole flow down. `cell.selfRating === null` therefore
 * skips the check.
 *
 * `cell.selfRating` is available without touching the query: the findMany uses
 * `include`, which returns every scalar column of reviewMonthlyScore.
 *
 * ── KNOWN GAP, DELIBERATELY NOT CLOSED HERE ─────────────────────────────────
 *
 * This constrains the MANAGER write. It does not stop an employee from later
 * LOWERING their self-rating below a manager score that is already stored,
 * which would leave the pair inconsistent from the other direction. That needs
 * a decision (re-open the manager cell? clamp? refuse the lower self?) rather
 * than a silent rule, so it is left alone and called out instead.
 */
import fs from 'fs';

const kraArg = process.argv.find((a) => a.startsWith('--kra='));
const KRA = kraArg
  ? kraArg.slice('--kra='.length)
  : 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const SVC = `${KRA}/features/reviews/reviews.service.js`;
const DRY = process.argv.includes('--dry');

const EDITS = [
  {
    id: 'manager-ceiling',
    marker: 'cannot exceed the employee',
    find: [
      '            const newRating = input.side === \'SELF\' ? update.selfRating : update.managerRating;',
      '            if (newRating !== undefined && newRating !== null) {',
      '                const max = Number(cell.reviewRow.maxScore);',
      '                if (newRating > max) {',
      '                    throw new http_errors_1.BadRequestError(`Rating ${newRating} exceeds max ${max}`);',
      '                }',
      '            }',
    ].join('\n'),
    replace: [
      '            const newRating = input.side === \'SELF\' ? update.selfRating : update.managerRating;',
      '            if (newRating !== undefined && newRating !== null) {',
      '                const max = Number(cell.reviewRow.maxScore);',
      '                if (newRating > max) {',
      '                    throw new http_errors_1.BadRequestError(`Rating ${newRating} exceeds max ${max}`);',
      '                }',
      '                // The self-rating is the manager\'s CEILING: their job is to',
      '                // moderate the employee\'s number, not to raise it.',
      '                //',
      '                // Only when a self score exists. An ABSENT self-rating is no',
      '                // ceiling, NOT a ceiling of zero — under ADMIN_ONLY there is',
      '                // no self-rating stage at all, and treating null as 0 would',
      '                // refuse every HR, Accounts and management write and take',
      '                // that whole flow down.',
      '                //',
      '                // This is the single choke point for all three manager write',
      '                // paths: the matrix auto-save posts here directly, and both',
      '                // /manager/reviews/:id/manager-rate handlers delegate here.',
      '                if (input.side === \'MANAGER\' &&',
      '                    cell.selfRating !== null &&',
      '                    cell.selfRating !== undefined) {',
      '                    const self = Number(cell.selfRating);',
      '                    if (newRating > self) {',
      '                        throw new http_errors_1.BadRequestError(`Manager rating ${newRating} cannot exceed the employee\'s self rating of ${self}`);',
      '                    }',
      '                }',
      '            }',
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
  const hits = src.split(find).length - 1;
  if (hits !== 1) {
    console.error(`  FAIL   ${e.id} — anchor matched ${hits} times, expected 1`);
    failed++;
    continue;
  }
  src = src.replace(find, N(e.replace));
  console.log(`  ${DRY ? 'WOULD ' : 'OK    '} ${e.id}`);
  applied++;
}
if (failed > 0) {
  console.error(`\nFAILED — ${failed} anchor(s) did not match. NOTHING written.`);
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
fs.copyFileSync(SVC, `${SVC}.bak`);
fs.writeFileSync(SVC, src, 'utf8');
console.log(`applied=${applied} skipped=${skipped}`);
console.log('');
console.log(`Syntax-check:  node --check ${SVC}`);
console.log('');
console.log('Verify:');
console.log('  employee self-rates 90, manager tries 95  -> 400, message names both');
console.log('  manager tries 90                          -> accepted (equal is fine)');
console.log('  manager tries 85                          -> accepted');
console.log('  ADMIN_ONLY KRA with NO self score, HR/Accounts/mgmt rate 100 -> accepted');
console.log('');
console.log(`  restore: copy reviews.service.js.bak reviews.service.js`);
