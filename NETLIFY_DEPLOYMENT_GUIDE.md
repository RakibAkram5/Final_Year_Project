# Flutter web on Netlify

Configuration: `netlify.toml` + `tool/netlify_build_web.sh` (Flutter 3.47.9).

| Concern | How it is handled |
|---|---|
| Build | `bash tool/netlify_build_web.sh` → `build/web` |
| API URL | none needed: the app calls `${origin}/api/v2`; Netlify proxies `/api/*` and `/health` to `https://taleemplus.vercel.app` (status 200 rewrite), so the browser sees one origin and needs no CORS |
| Deep links / refresh | SPA fallback `/* → /index.html 200`, declared **after** the API proxy |
| Caching | `index.html`, `main.dart.js`, `flutter_bootstrap.js`, service worker: `no-cache`; engine/assets/icons: 1 day + revalidate |
| Security headers | `X-Content-Type-Options`, `X-Frame-Options: DENY`, HSTS, `Referrer-Policy` |
| Permissions-Policy | **changed in this release** to `geolocation=(self)` so an admin can use "Use my current position" on the academy-location page (was `geolocation=()`, which blocked it) |
| Secrets | none: no backend secret lives on Netlify |

Maps: tiles load from `https://tile.openstreetmap.org` (no key); no CSP is set,
so nothing extra is needed. If you add a Content-Security-Policy later, allow
`img-src https://tile.openstreetmap.org`.

## Deploy (needs your approval)

Push to the connected branch, or `netlify deploy --prod --dir build/web` after
building locally. Verify:

```powershell
curl -I https://<site>.netlify.app/                # 200, no-cache on index.html
curl https://<site>.netlify.app/health             # proxied backend health
curl -I https://<site>.netlify.app/some/deep/link  # 200 (SPA fallback)
```

Mobile layout was verified with automated widget tests at 320–2560 px (see
`RESPONSIVE_UI_TEST_REPORT.md`); a manual browser pass was **not** performed in
this session because the browser extension was not connected.
