# Deploying the KRA app to Cloudflare Pages

The app is a Flutter **web** build (static files) served on Cloudflare as a
Workers static-assets site. Config lives in `wrangler.toml` (`[assets]` +
`not_found_handling = single-page-application` for SPA routing) and
`web/_headers` (cache control) — `web/_headers` is copied verbatim into
`build/web/` by `flutter build web`. Do NOT add a `_redirects` file: a
`/* -> /index.html` rule is rejected by Cloudflare as an infinite loop, and
`not_found_handling` already handles the SPA fallback.

## One-time setup
```bash
flutter --version          # ensure the Flutter SDK is installed
npm i -g wrangler          # or use npx wrangler ...
wrangler login             # authorise against your Cloudflare account
```

## Build
```bash
flutter pub get
flutter build web --release
```
Output goes to `build/web/`. The monthly-review backend is gated on a build
flag (default off); once that backend is deployed, build with:
```bash
flutter build web --release --dart-define=MONTHLY_BACKEND=true
```
(Optional) if you ever serve the app under a sub-path instead of the domain
root, add `--base-href /your-subpath/` (must start and end with `/`).

## Deploy — Workers static assets
The app is configured (`wrangler.toml` → `[assets]`) as a Cloudflare Workers
static-assets site, so the standard deploy command works with no extra flags:
```bash
npx wrangler deploy          # uploads build/web (the [assets] directory)
```
First deploy creates the `vistar-kra` Worker and returns a
`https://vistar-kra.<your-subdomain>.workers.dev` URL. Add a custom domain in
the dashboard (Workers & Pages → the project → Domains & Routes) if wanted.
SPA routing is handled by `not_found_handling = "single-page-application"`.

## Git integration (Cloudflare builds + deploys on push)
Connect the repo in the dashboard (Workers & Pages) and set:
- **Build command:**
  ```
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter" && git config --global --add safe.directory "$HOME/flutter" && export PATH="$HOME/flutter/bin:$PATH" && flutter config --no-analytics && flutter pub get && flutter build web --release
  ```
- **Deploy command:** `npx wrangler deploy`  (the default)
- **Build output / assets directory:** `build/web` (already in wrangler.toml)

The build image has no Flutter SDK, so it's cloned each build (~3–6 min first
run). Verified working: the Flutter build succeeds and wrangler reads all
files from build/web.

## IMPORTANT — backend CORS
Unlike the mobile app, a browser enforces CORS. The API at
`https://vistar-crm.onrender.com/api/v1/kra` MUST send
`Access-Control-Allow-Origin` for the deployed origin (e.g.
`https://vistar-kra.pages.dev` and any custom domain) plus allow the
`Authorization` header and the methods used (GET/POST/PATCH/DELETE) and
preflight `OPTIONS`. Without this, every API call fails in the browser even
though the app loads. Coordinate this with the backend team before go-live.

## Notes
- `build/` is gitignored — don't commit the compiled output.
- SPA fallback (`not_found_handling = "single-page-application"`) makes deep
  links like `/hr/home` work on refresh; existing static assets resolve
  normally (they're matched before the not-found handler runs).
- The Worker `name` in `wrangler.toml` must match the connected project
  (`kra`), or Cloudflare overrides it and opens a config-fix PR.
