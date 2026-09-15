// Lifts findCurrentMonth VERBATIM from the file and exercises it. Not retyped,
// so this cannot drift from what ships.
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
const m = src.match(/function findCurrentMonth\(months\) \{[\s\S]*?\n\}/);
if (!m) throw new Error('could not lift findCurrentMonth');
const patched = /const under = new Date\(Date\.UTC\(/.test(m[0]);

// The function calls `new Date()` for "now", so fake the clock around it.
const RealDate = Date;
function withClock(iso, fn) {
  global.Date = class extends RealDate {
    constructor(...a) { return a.length ? new RealDate(...a) : new RealDate(iso); }
    static UTC(...a) { return RealDate.UTC(...a); }
    static now() { return new RealDate(iso).getTime(); }
  };
  try { return fn(); } finally { global.Date = RealDate; }
}
const findCurrentMonth = eval(`(${m[0]})`);

const month = (y, mo, status = 'OPEN') => ({
  monthLabel: `${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][mo-1]}-${String(y).slice(2)}`,
  monthDate: new RealDate(RealDate.UTC(y, mo - 1, 1)),
  status,
});

const cases = [
  ['2026-09-09T10:00:00Z', [month(2026,7),month(2026,8),month(2026,9)], 'Aug-26', 'mid-September rates August'],
  ['2026-09-01T00:30:00Z', [month(2026,7),month(2026,8),month(2026,9)], 'Aug-26', 'the 1st still rates the month just ended'],
  ['2026-09-30T23:59:00Z', [month(2026,7),month(2026,8),month(2026,9)], 'Aug-26', 'the last day of Sep still rates August'],
  ['2027-01-04T09:00:00Z', [month(2026,11),month(2026,12),month(2027,1)], 'Dec-26', 'JANUARY ROLLS BACK TO DECEMBER OF THE PRIOR YEAR'],
  ['2026-10-05T09:00:00Z', [month(2026,7),month(2026,8),month(2026,9)], 'Sep-26', 'October rates September'],
];

let pass = 0; const fails = [];
console.log(`gate: ${patched ? 'PATCHED (previous month)' : 'DEPLOYED (today\'s month)'}`);
for (const [iso, months, expected, why] of cases) {
  const got = withClock(iso, () => findCurrentMonth(months));
  const label = got ? got.monthLabel : '(null)';
  if (label === expected) pass++;
  else fails.push(`  WRONG  ${iso.slice(0,10)} -> ${label}, expected ${expected}   (${why})`);
}
// Fallbacks must survive: a cycle with no month for the open period.
const early = withClock('2026-09-09T10:00:00Z', () => findCurrentMonth([month(2026,9)]));
if (early && early.monthLabel === 'Sep-26') pass++;
else fails.push('  WRONG  fallback: a cycle whose only month is the live one must still return it');

for (const f of fails) console.log(f);
console.log(`  ${pass}/${cases.length + 1} as intended`);
process.exitCode = fails.length ? 1 : 0;
