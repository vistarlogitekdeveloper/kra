// Inventory, back up, and (optionally) clear the KRA review data for a fresh
// demo start.
//
// Usage:
//   KRA_EMAIL=... KRA_PASSWORD='...' node scripts/reset-reviews.mjs
//   KRA_EMAIL=... KRA_PASSWORD='...' node scripts/reset-reviews.mjs --apply --confirm=DELETE-ALL-REVIEWS
//
// READ-ONLY BY DEFAULT. It lists exactly what exists and writes a full JSON
// backup, and touches nothing else. Deleting requires BOTH --apply and the
// literal --confirm token, because this is irreversible: review scores and
// settled incentive amounts cannot be reconstructed from anything else.
//
// The backup is written before any delete is attempted, and the run aborts if
// it cannot be written.
//
// ── Two stores, not one ──────────────────────────────────────────────────────
// Review state lives in BOTH `kra.monthly_reviews` (the quarterly KRA sheet,
// via /reviews/monthly) and the legacy `kra.reviews` table (which still feeds
// /employee/dashboard — see monthly_review_providers.dart). Clearing only one
// leaves the home dashboard showing stale "Self-rating pending" cards, so a
// genuine fresh start has to cover both. The client has no endpoint for the
// legacy table, so this script reports it and leaves it to the backend.
//
// ── What it does NOT touch ───────────────────────────────────────────────────
// Employees, KRA templates, KRA assignments, project locations and bonus slabs
// are all left alone: those are the setup a demo needs to still be there
// afterwards. Only cycles and review records are in scope.

import { writeFileSync } from 'node:fs';

const BASE = process.env.KRA_BASE ?? 'https://vistar-crm.onrender.com/api/v1/kra';
const EMAIL = process.env.KRA_EMAIL;
const PASSWORD = process.env.KRA_PASSWORD;
/// Alternative to email+password: a bearer token copied from the browser
/// (devtools → Network → any request → Authorization header). Short-lived, so
/// it's the safer way to authorise a one-off read-only verification.
const TOKEN = process.env.KRA_TOKEN;
const APPLY = process.argv.includes('--apply');
const CONFIRMED = process.argv.includes('--confirm=DELETE-ALL-REVIEWS');

/// Months to sweep for monthly reviews. Reviews are addressed by year+month, so
/// there is no "list everything" call — override with --from=2025-04 --to=2026-12.
const arg = (name, fallback) =>
  (process.argv.find((a) => a.startsWith(`--${name}=`)) ?? `=${fallback}`).split('=').pop();
const FROM = arg('from', '2025-01');
const TO = arg('to', '2026-12');

let token = null;

async function api(method, path, { allowFail = false } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || json.success === false) {
    if (allowFail) return { __failed: true, status: res.status, error: json.error };
    const e = json.error ?? {};
    throw new Error(`${method} ${path} → ${res.status} ${e.code ?? ''} ${e.message ?? ''}`.trim());
  }
  return json.data;
}

function monthsBetween(from, to) {
  const [fy, fm] = from.split('-').map(Number);
  const [ty, tm] = to.split('-').map(Number);
  const out = [];
  for (let y = fy, m = fm; y < ty || (y === ty && m <= tm); m === 12 ? (m = 1, y++) : m++) {
    out.push({ year: y, month: m });
  }
  return out;
}

async function main() {
  if (!TOKEN && (!EMAIL || !PASSWORD)) {
    console.error(
      'Set KRA_EMAIL and KRA_PASSWORD (an HR-admin account), or KRA_TOKEN\n' +
        'with a bearer copied from the browser for a read-only check.',
    );
    process.exit(1);
  }
  if (APPLY && !CONFIRMED) {
    console.error(
      '--apply requires --confirm=DELETE-ALL-REVIEWS.\n' +
        'This permanently deletes review scores and settled incentive amounts.',
    );
    process.exit(1);
  }

  if (TOKEN) {
    // Verification only needs a read; a short-lived bearer copied from the
    // browser's devtools avoids handing over a password at all.
    token = TOKEN;
  } else {
    const res = await fetch(`${BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
    });
    const json = await res.json().catch(() => ({}));
    if (!json?.data?.accessToken) {
      throw new Error(`Login failed: ${JSON.stringify(json.error ?? json)}`);
    }
    token = json.data.accessToken;
  }

  console.log(`Connected to ${BASE}\n`);

  // ── Inventory ──────────────────────────────────────────────────────────────
  const cycles = (await api('GET', '/review-cycles?page=1&limit=200')).reviewCycles ?? [];
  console.log(`Review cycles: ${cycles.length}`);
  cycles.forEach((c) => console.log(`  ${c.id}  ${c.name ?? ''}  ${c.status ?? ''}`));

  const months = monthsBetween(FROM, TO);
  console.log(`\nSweeping ${months.length} months (${FROM} … ${TO}) for monthly reviews…`);
  const monthly = [];
  for (const { year, month } of months) {
    const data = await api('GET', `/reviews/monthly?year=${year}&month=${month}`, { allowFail: true });
    if (data?.__failed) continue;
    const list = Array.isArray(data) ? data : (data?.reviews ?? data?.items ?? []);
    for (const r of list) monthly.push({ year, month, ...r });
  }

  const withActivity = monthly.filter(
    (r) => Number(r.finalScorePct ?? 0) > 0 || r.selfScorePct != null || r.managementReviewPct != null,
  );
  const byMonth = monthly.reduce((acc, r) => {
    const k = `${r.year}-${String(r.month).padStart(2, '0')}`;
    acc[k] = (acc[k] ?? 0) + 1;
    return acc;
  }, {});

  console.log(`\nMonthly reviews: ${monthly.length} total, ${withActivity.length} carrying scores`);
  Object.entries(byMonth).forEach(([k, n]) => console.log(`  ${k}: ${n}`));
  if (withActivity.length) {
    console.log('\n  Rows with real scores that would be LOST:');
    withActivity.forEach((r) =>
      console.log(
        `    ${r.year}-${String(r.month).padStart(2, '0')}  ${r.employeeName ?? r.employeeId}  ` +
          `${r.finalScorePct ?? 0}%  ${r.payoutStatus ?? ''}`,
      ),
    );
  }

  // ── Backup (always, before any delete) ─────────────────────────────────────
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const file = `review-backup-${stamp}.json`;
  try {
    writeFileSync(file, JSON.stringify({ takenAt: stamp, base: BASE, cycles, monthly }, null, 2));
    console.log(`\n✓ Backup written: ${file}`);
  } catch (e) {
    console.error(`\n✗ Could not write backup (${e.message}) — refusing to delete.`);
    process.exit(1);
  }

  if (!APPLY) {
    console.log('\nDRY RUN — nothing deleted.');
    console.log('To delete: --apply --confirm=DELETE-ALL-REVIEWS');
    return;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  // The client never deletes reviews or cycles, so these endpoints are unproven.
  // Try one first and stop early if the API doesn't support it, rather than
  // firing hundreds of requests that all fail.
  console.log('\nDeleting monthly reviews…');
  let deleted = 0;
  const unsupported = [];
  for (const r of monthly) {
    const out = await api('DELETE', `/reviews/monthly/${r.id}`, { allowFail: true });
    if (out?.__failed) {
      if (out.status === 404 || out.status === 405) {
        unsupported.push(`DELETE /reviews/monthly/:id → ${out.status}`);
        break;
      }
      console.log(`  ! ${r.id}: ${out.error?.message ?? out.status}`);
      continue;
    }
    deleted++;
  }
  console.log(`  deleted ${deleted}/${monthly.length}`);

  console.log('\nDeleting review cycles…');
  let cyclesDeleted = 0;
  for (const c of cycles) {
    const out = await api('DELETE', `/review-cycles/${c.id}`, { allowFail: true });
    if (out?.__failed) {
      if (out.status === 404 || out.status === 405) {
        unsupported.push(`DELETE /review-cycles/:id → ${out.status}`);
        break;
      }
      console.log(`  ! ${c.id}: ${out.error?.message ?? out.status}`);
      continue;
    }
    cyclesDeleted++;
  }
  console.log(`  deleted ${cyclesDeleted}/${cycles.length}`);

  if (unsupported.length) {
    console.log('\n⚠ The API does not expose delete for:');
    [...new Set(unsupported)].forEach((u) => console.log(`  - ${u}`));
    console.log(
      '\n  This has to be done backend-side (truncate the review tables).\n' +
        '  Remember the LEGACY kra.reviews table too — /employee/dashboard reads\n' +
        '  from it, so leaving it populated keeps stale cards on the home screen.',
    );
  }
}

main().catch((e) => {
  console.error(`\n✗ ${e.message}`);
  process.exit(1);
});
