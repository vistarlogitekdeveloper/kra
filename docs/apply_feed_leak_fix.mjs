/**
 * Patches the cross-tenant leak in the three feed list endpoints.
 *
 * NOT SQL. This is a Node script that edits three backend JavaScript files.
 * Do not paste it into pgAdmin — the database is not involved at all.
 *
 * HOW TO RUN (PowerShell or cmd, not pgAdmin):
 *
 *     node D:\Vistar\krafrontend\docs\apply_feed_leak_fix.mjs
 *
 * Add --dry to preview without writing:
 *
 *     node D:\Vistar\krafrontend\docs\apply_feed_leak_fix.mjs --dry
 *
 * Safe to run twice: it detects an already-patched file and skips it.
 * Every file it changes is backed up alongside as <name>.bak first.
 *
 * WHAT IT FIXES
 * -------------
 * Each feed's list() builds:
 *
 *     const where = {
 *         month: { reviewCycle: { organizationId: actor.organizationId } },
 *     };
 *
 * ...then later REASSIGNS that key:
 *
 *     if (query.reviewCycleId)
 *         where.month = { reviewCycleId: query.reviewCycleId };
 *
 * `where.month` held the only organisation predicate on the query, so the
 * reassignment removes tenant scoping entirely. Because the three list routes
 * carry no role guard (only `authenticate`), ANY signed-in user — including a
 * plain EMPLOYEE — can read every organisation's feed rows via
 * ?reviewCycleId=<any id>.
 *
 * The patch merges the two conditions instead of replacing one with the other.
 *
 * AFTER RUNNING: restart / redeploy the API. Editing files on disk changes
 * nothing until the running process reloads them.
 */
import fs from 'fs';
import path from 'path';

const BASE = 'D:/Vistar/vistar_CRM/src/modules/kra/dist/features/feeds';
const DRY = process.argv.includes('--dry');

const NOTE = [
  '        // MERGE, never reassign. `where.month` carries the ONLY organisation',
  '        // predicate on this query (month.reviewCycle.organizationId, set',
  '        // above). Overwriting it with a bare { reviewCycleId } dropped that',
  '        // predicate entirely, so any authenticated user could read EVERY',
  "        // organisation's feed rows by supplying ?reviewCycleId=<any id>.",
  '        if (query.reviewCycleId) {',
  '            where.month = {',
  '                reviewCycle: { organizationId: actor.organizationId },',
  '                reviewCycleId: query.reviewCycleId,',
  '            };',
  '        }',
].join('\n');

// hr-feed and accounts-feed write the guard over two lines; ops-feed over one.
const TARGETS = [
  {
    file: `${BASE}/hr-feed/hr-feed.service.js`,
    find:
      '        if (query.reviewCycleId)\n' +
      '            where.month = { reviewCycleId: query.reviewCycleId };',
  },
  {
    file: `${BASE}/accounts-feed/accounts-feed.service.js`,
    find:
      '        if (query.reviewCycleId)\n' +
      '            where.month = { reviewCycleId: query.reviewCycleId };',
  },
  {
    file: `${BASE}/ops-feed/ops-feed.service.js`,
    find:
      '        if (query.reviewCycleId) where.month = { reviewCycleId: query.reviewCycleId };',
  },
];

const ALREADY = 'reviewCycle: { organizationId: actor.organizationId },\n                reviewCycleId:';

let patched = 0;
let skipped = 0;
let failed = 0;

for (const t of TARGETS) {
  const name = path.basename(t.file);

  if (!fs.existsSync(t.file)) {
    console.error(`  FAIL   ${name} — file not found at ${t.file}`);
    failed++;
    continue;
  }

  let src = fs.readFileSync(t.file, 'utf8');
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const toEol = (s) => s.split('\n').join(eol);

  if (src.includes(toEol(ALREADY))) {
    console.log(`  SKIP   ${name} — already patched`);
    skipped++;
    continue;
  }

  const find = toEol(t.find);
  const hits = src.split(find).length - 1;
  if (hits !== 1) {
    console.error(
      `  FAIL   ${name} — expected exactly 1 match, found ${hits}. ` +
        `Patch it by hand; see docs/SECURITY_cross_org_feed_leak.md`,
    );
    failed++;
    continue;
  }

  const out = src.replace(find, toEol(NOTE));

  if (DRY) {
    console.log(`  WOULD  ${name} — 1 replacement`);
    patched++;
    continue;
  }

  fs.copyFileSync(t.file, `${t.file}.bak`);
  fs.writeFileSync(t.file, out, 'utf8');
  console.log(`  OK     ${name} — patched (backup: ${name}.bak)`);
  patched++;
}

// ── Verify ──────────────────────────────────────────────────────────────────
console.log('');
let verified = 0;
for (const t of TARGETS) {
  if (!fs.existsSync(t.file)) continue;
  const src = fs.readFileSync(t.file, 'utf8');
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  if (src.includes(ALREADY.split('\n').join(eol))) verified++;
}
console.log(
  `verify: ${verified}/3 files now scope the reviewCycleId branch by organisation`,
);
console.log(
  `patched=${patched} skipped=${skipped} failed=${failed}${DRY ? '  (dry run — nothing written)' : ''}`,
);

if (!DRY && verified === 3) {
  console.log('');
  console.log('Next: restart / redeploy the API — file edits do not affect the');
  console.log('running process until it reloads.');
  console.log('');
  console.log('Then confirm with a request that used to leak:');
  console.log('  GET /api/v1/kra/feeds/hr?reviewCycleId=<a cycle in ANOTHER org>');
  console.log('  -> expect 0 rows, not that org\'s rows.');
}

process.exit(failed > 0 ? 1 : 0);
