/**
 * Installs the /organizations API into the KRA backend.
 *
 * NOT SQL, and nothing here is meant to be pasted into a shell or pgAdmin —
 * run the whole file with node:
 *
 *     node D:\Vistar\krafrontend\docs\install_organizations_api.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_organizations_api.mjs
 *
 * It does both remaining steps for you:
 *
 *   1. creates  dist/features/organizations/organizations.routes.js
 *      from docs/backend_patch_organizations.js (stripping that file's
 *      instructional header, keeping the code)
 *   2. edits    dist/app.js  — adds the require and the app.use mount,
 *      placed beside the existing locations router
 *
 * Idempotent: re-running detects both steps and skips. app.js is backed up as
 * app.js.bak before it is touched.
 *
 * AFTER RUNNING: restart / redeploy the API. Editing files on disk changes
 * nothing until the running process reloads them.
 */
import fs from 'fs';
import path from 'path';

const DIST = 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const SRC = 'D:/Vistar/krafrontend/docs/backend_patch_organizations.js';
const OUT_DIR = `${DIST}/features/organizations`;
const OUT = `${OUT_DIR}/organizations.routes.js`;
const APP = `${DIST}/app.js`;
const DRY = process.argv.includes('--dry');

const HEADER = `"use strict";
/**
 * Organizations — SUPER_ADMIN only.
 *
 * The Organization model has existed since the beginning
 * (prisma/schema.prisma -> kra.organizations) and organizationId threads
 * through ~732 places, but there was NO API for it: no route, controller or
 * service anywhere in this module. So an organisation could never be created,
 * renamed or listed through the product — only inserted by hand in SQL.
 *
 * Scoping note: every other router scopes by req.user.organizationId, which is
 * signed into the JWT at login. This router must NOT — an organisation-wide
 * admin has to see organisations it is not currently "inside". Access is
 * therefore gated purely on the SUPER_ADMIN role.
 *
 * POST /switch re-issues the token pair against a different organisation,
 * which is how a super admin acts on another tenant: it is the only mechanism
 * available, because every downstream repository reads the JWT claim rather
 * than a request parameter.
 */
`;

let failed = 0;

// ── Step 1: the router file ─────────────────────────────────────────────────
function installRouter() {
  if (fs.existsSync(OUT)) {
    const existing = fs.readFileSync(OUT, 'utf8');
    if (existing.includes('organizationsRouter')) {
      console.log('  SKIP   organizations.routes.js — already present');
      return true;
    }
    console.error('  FAIL   organizations.routes.js exists but looks wrong — inspect it by hand');
    failed++;
    return false;
  }

  if (!fs.existsSync(SRC)) {
    console.error(`  FAIL   source not found: ${SRC}`);
    failed++;
    return false;
  }

  const raw = fs.readFileSync(SRC, 'utf8');
  // The docs copy opens with an instructional block comment ("READY TO
  // APPLY…"), which has no business in deployed source. Everything from the
  // "use strict" directive onward is the real module.
  const marker = '"use strict";';
  const at = raw.indexOf(marker);
  if (at === -1) {
    console.error('  FAIL   could not find the "use strict" marker in the source');
    failed++;
    return false;
  }
  const body = raw.slice(at + marker.length).replace(/^\r?\n/, '');
  const out = HEADER + body;

  // Sanity-check before writing: a truncated copy would 500 the whole app on
  // boot, since app.js requires this at startup.
  for (const needle of ['organizationsRouter', "requireRoles)('SUPER_ADMIN')", '/switch']) {
    if (!out.includes(needle)) {
      console.error(`  FAIL   assembled file is missing ${needle} — refusing to write`);
      failed++;
      return false;
    }
  }

  if (DRY) {
    console.log(`  WOULD  create organizations.routes.js (${out.length} bytes)`);
    return true;
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(OUT, out, 'utf8');
  console.log(`  OK     created ${path.relative(DIST, OUT).replace(/\\/g, '/')}`);
  return true;
}

// ── Step 2: mount it in app.js ──────────────────────────────────────────────
function mountRouter() {
  if (!fs.existsSync(APP)) {
    console.error(`  FAIL   app.js not found at ${APP}`);
    failed++;
    return false;
  }

  let src = fs.readFileSync(APP, 'utf8');
  const eol = src.includes('\r\n') ? '\r\n' : '\n';

  if (src.includes('organizations_routes_1')) {
    console.log('  SKIP   app.js — already mounts /organizations');
    return true;
  }

  // Anchor 1 — the require block. Placed after the locations require so it
  // sits with its neighbours rather than at the end of the list.
  const reqAnchor = 'const locations_routes_1 = require("./features/locations/locations.routes");';
  // Anchor 2 — the mount. Placed after the /locations mounts, before /hr/*.
  const useAnchor = 'app.use(`${env_1.env.API_PREFIX}/hr/locations`, locations_routes_1.locationsRouter);';

  for (const [name, a] of [['require', reqAnchor], ['app.use', useAnchor]]) {
    const hits = src.split(a).length - 1;
    if (hits !== 1) {
      console.error(`  FAIL   app.js ${name} anchor matched ${hits} times, expected 1 — mount by hand`);
      failed++;
      return false;
    }
  }

  const reqLine =
    'const organizations_routes_1 = require("./features/organizations/organizations.routes");';
  const useLines = [
    '    // Tenant administration — SUPER_ADMIN only. Unlike every other router',
    '    // here this one is NOT scoped to the caller\'s organisation, because an',
    '    // organisation-wide admin must see tenants it is not currently inside.',
    '    app.use(`${env_1.env.API_PREFIX}/organizations`, organizations_routes_1.organizationsRouter);',
  ].join(eol);

  const out = src
    .replace(reqAnchor, reqAnchor + eol + reqLine)
    .replace(useAnchor, useAnchor + eol + useLines);

  if (DRY) {
    console.log('  WOULD  add the require + app.use to app.js');
    return true;
  }

  fs.copyFileSync(APP, `${APP}.bak`);
  fs.writeFileSync(APP, out, 'utf8');
  console.log('  OK     app.js mounted /organizations (backup: app.js.bak)');
  return true;
}

console.log(DRY ? 'DRY RUN — nothing will be written\n' : '');
installRouter();
mountRouter();

// ── Verify ──────────────────────────────────────────────────────────────────
console.log('');
if (DRY) {
  console.log('dry run complete — re-run without --dry to apply');
} else {
  const routerOk =
    fs.existsSync(OUT) && fs.readFileSync(OUT, 'utf8').includes('organizationsRouter');
  const mountOk =
    fs.existsSync(APP) && fs.readFileSync(APP, 'utf8').includes('organizations_routes_1');
  console.log(`verify: router file ${routerOk ? 'OK' : 'MISSING'}, app.js mount ${mountOk ? 'OK' : 'MISSING'}`);

  if (routerOk && mountOk && failed === 0) {
    console.log('');
    console.log('Next:');
    console.log('  1. restart / redeploy the API (file edits do nothing until it reloads)');
    console.log('  2. sign in as superadmin@vistar.test and check:');
    console.log('       GET /api/v1/kra/organizations   -> 200 with your 4 tenants');
    console.log('     it currently answers 404 RES_001.');
    console.log('');
    console.log('  If the API fails to boot, restore with:');
    console.log('       copy app.js.bak app.js');
    console.log('     and delete features/organizations/.');
  }
}

process.exit(failed > 0 ? 1 : 0);
