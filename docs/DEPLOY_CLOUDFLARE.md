# Deploying the KRA app to Cloudflare Pages

The app is a Flutter **web** build (static files) served on Cloudflare Pages.
Config lives in `wrangler.toml`, `web/_redirects` (SPA fallback) and
`web/_headers` (cache control) — the two `web/*` files are copied verbatim
into `build/web/` by `flutter build web`.

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

## Deploy (direct upload — recommended)
```bash
npx wrangler pages deploy            # reads pages_build_output_dir from wrangler.toml
# or explicitly:
npx wrangler pages deploy build/web --project-name=vistar-kra
```
The first deploy creates the `vistar-kra` project and returns a
`https://vistar-kra.pages.dev` URL. Add a custom domain in the Cloudflare
dashboard (Pages → the project → Custom domains) if wanted.

## Alternative: Pages Git integration (Cloudflare builds on push)
Connect the repo in the Cloudflare dashboard and set:
- **Build command:**
  ```
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter" && export PATH="$PATH:$HOME/flutter/bin" && flutter pub get && flutter build web --release
  ```
- **Build output directory:** `build/web`
(The Pages build image has no Flutter SDK, so it's cloned each build — slower
than the direct-upload path above.)

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
- SPA fallback (`web/_redirects`) makes deep links like `/hr/home` work on
  refresh; static assets still resolve normally (Pages serves existing files
  before applying the fallback).
