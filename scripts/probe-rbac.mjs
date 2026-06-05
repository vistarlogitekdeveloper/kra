// Live backend role-enforcement probe.
//
// Usage:
//   node scripts/probe-rbac.mjs
//
// Logs in with each known test-account email, then probes a set of
// HR / Manager / Shared endpoints and prints a verdict per cell.
// LEAK rows mean the server returned 200 to a role that should have
// received 403 — every LEAK is a backend bug.
//
// Re-run after each backend change to RBAC middleware. See
// docs/BACKEND_RBAC_FINDINGS.md for the latest results and the
// expected baseline.

const BASE = 'https://vistar-crm.onrender.com/api/v1/kra';

const ROLE_CANDIDATES = {
  EMPLOYEE: [
    'employee@vistar.test', 'emp@vistar.test', 'user@vistar.test',
    'staff@vistar.test', 'test@vistar.test',
  ],
  MANAGER:  ['manager@vistar.test', 'mgr@vistar.test'],
  HR:       ['hr@vistar.test', 'hradmin@vistar.test', 'admin@vistar.test',
             'kraadmin@vistar.test', 'hrops@vistar.test'],
};

const PASSWORD = 'Vistar@123';

const HR_ENDPOINTS = [
  '/employees?page=1&pageSize=5',
  '/kra-templates?page=1&pageSize=5',
  '/review-cycles?page=1&pageSize=5',
  '/locations?page=1&pageSize=5',
  '/kra-assignments?page=1&pageSize=5',
  '/bonus-slabs?page=1&pageSize=5',
  '/hr/dashboard',
  '/hr/dashboard/recent-activity?limit=15',
];

const MANAGER_ENDPOINTS = [
  '/manager/dashboard',
  '/manager/team?page=1&limit=5',
];

const SHARED_ENDPOINTS = [
  '/auth/me',
  '/employee/profile',
];

async function tryLogin(email, password) {
  try {
    const res = await fetch(`${BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    if (!res.ok) return null;
    const json = await res.json();
    const token =
      json?.data?.tokenPair?.accessToken ??
      json?.data?.accessToken ??
      json?.accessToken;
    if (!token) return null;
    const role = json?.data?.user?.role ?? json?.data?.role ?? '(unknown)';
    return { email, token, role };
  } catch (_) {
    return null;
  }
}

async function findAccountForRole(candidates) {
  for (const email of candidates) {
    const ok = await tryLogin(email, PASSWORD);
    if (ok) return ok;
  }
  return null;
}

async function probe(token, path) {
  try {
    const res = await fetch(`${BASE}${path}`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` },
    });
    return res.status;
  } catch (e) {
    return `ERR:${e.message.slice(0, 60)}`;
  }
}

function verdict(role, group, status) {
  if (group === 'HR') {
    const isAllowed = ['HR_ADMIN', 'HR', 'ADMIN'].includes(role);
    if (isAllowed) return status === 200 ? '✅ 200' : `⚠ ${status}`;
    if (status === 403) return '✅ 403';
    if (status === 401) return '⚠ 401';
    if (status === 404) return `· 404`;
    if (status === 200) return '🔴 200 LEAK';
    return `· ${status}`;
  }
  if (group === 'MGR') {
    const isAllowed = ['MANAGER', 'HR_ADMIN', 'ADMIN', 'BD_MANAGER',
                       'WAREHOUSE_MGR'].includes(role);
    if (isAllowed) return status === 200 ? '✅ 200' : `⚠ ${status}`;
    if (status === 403) return '✅ 403';
    if (status === 200) return '🔴 200 LEAK';
    return `· ${status}`;
  }
  return status === 200 ? '✅ 200' : `⚠ ${status}`;
}

function pad(s, n) { return String(s).padEnd(n); }

async function main() {
  console.log('Searching for test accounts...');
  const found = {};
  for (const [role, list] of Object.entries(ROLE_CANDIDATES)) {
    const acct = await findAccountForRole(list);
    if (acct) {
      found[role] = acct;
      console.log(`  ${pad(role, 10)} → ${acct.email} (role=${acct.role})`);
    } else {
      console.log(`  ${pad(role, 10)} → no working account`);
    }
  }
  const accounts = Object.entries(found);
  if (!accounts.length) {
    console.log('\nNo accounts could log in. Aborting.');
    return;
  }

  const groups = [
    ['HR endpoints (HR/HR_ADMIN/ADMIN may access)', 'HR', HR_ENDPOINTS],
    ['Manager endpoints (manager-capable roles may access)', 'MGR', MANAGER_ENDPOINTS],
    ['Shared endpoints (every authenticated user)', 'SHARED', SHARED_ENDPOINTS],
  ];

  for (const [title, code, endpoints] of groups) {
    console.log('\n=== ' + title + ' ===');
    const header = pad('endpoint', 50) +
      accounts.map(([role]) => pad(role, 16)).join('');
    console.log(header);
    for (const ep of endpoints) {
      const cells = [pad(ep, 50)];
      for (const [, acct] of accounts) {
        const status = await probe(acct.token, ep);
        cells.push(pad(verdict(acct.role, code, status), 16));
      }
      console.log(cells.join(''));
    }
  }
}

main().catch((e) => { console.error('FATAL:', e); process.exit(1); });
