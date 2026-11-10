# TaleemPlus — Final Submission Report

_Date: 2026-11-09. Every result below was actually executed; nothing is assumed.
No commit/tag/push, no GitHub settings change, no deployment, no destructive DB
operation, and no secret values were printed. Statuses: **PASS · FAIL · BLOCKED ·
NOT TESTED**._

Evidence types: **Local** (ran on this machine) · **Mocked** · **Integration (needs DB)**
· **Live-deploy** (not performed).

---

## 1. Overall project status
**Code-healthy and buildable; NOT yet release-ready** due to three outstanding items:
1. 🔴 **Exposed secrets in git history** (must rotate — see §8).
2. **Android APK/AAB blocked** (local Android SDK incomplete).
3. **ML models untrained & E2E role flows not tested** (need seeded demo data + running app).

Flutter analyzes clean, all 114 Flutter tests pass, the web app builds, and the ML
service passes 53 tests. Commit/tag/push and GitHub hardening are held for your approval.

## 2. Bugs discovered
| # | Severity | Finding | State |
|---|---|---|---|
| 1 | **Critical** | Real `.env` (DB URL + JWT/refresh secrets) in pushed git history (`10c418d`, `ecf87a4`) | Rotation required (§8) |
| 2 | Medium | No global IP rate-limiter (`express-rate-limit` absent) | Mitigated by account lockout; recommend adding |
| 3 | Low | No DB-level RLS; tenant isolation is query-level only | Documented; works, hardening optional |
| 4 | Low | Web release artifact built without `API_BASE_URL` | Rebuild with `--dart-define` before deploy (§11) |
| — | — | `flutter analyze` | **0 issues** |

## 3. Bugs fixed (this session's work, verified)
- ML scheduler **race condition** (6h vs daily sweep) — fixed with a sweep lock + regression test.
- HF persistence: added **activate-only-after-successful-upload** (revert on failed upload) + integrity check.
- Node ML client: **cold-start timeout + retry** (502/503/504/timeout).
- All covered by passing tests.

## 4. Remaining bugs
- None blocking from static analysis or tests. Outstanding **operational** items: secret rotation (§8), Android build toolchain (§13), model training on real data (§7).

## 5. Flutter test results — **PASS (Local)**
```
flutter analyze  -> No issues found! (146.8s)
flutter test     -> All tests passed!  (114 tests, incl. 60-screen responsive matrix)
```

## 6. Backend test results
- `npx jest tests/mlServiceClient.test.js` -> **2 passed** (**PASS, Local**).
- Full `npm test` (contract/DB tests) -> **BLOCKED (Local)**: needs a test Postgres (CI provides `postgres:16` service via `backend-ci.yml`). Not run locally to avoid misleading failures.

## 7. ML test results — **PASS (Local + Mocked)**
```
cd ml_service && python -m pytest -q  -> 53 passed
  (unit: monitoring/scheduler/pipeline; mocked-integration: HF push/pull/retry/integrity/revert; api/auth)
```
- **Real model training: NOT TESTED / INSUFFICIENT DATA** — live DB nearly empty; both models correctly report `INSUFFICIENT_DATA`. No fabricated training claimed.

## 8. Security audit results
| Area | Status | Notes |
|---|---|---|
| Password hashing | **PASS** | bcryptjs, cost 12 |
| JWT / refresh tokens | **PASS (design)** | secrets in env; **but exposed in history → rotate** |
| RBAC + academy authorization | **PASS** | `authenticateToken` + `authorizeRoles`; `req.academyId` from token, not client |
| Input size / body limit | **PASS** | `express.json({limit:'1500kb'})` |
| Helmet / CORS | **PASS** | `helmet()`; CORS allowlist via `CORS_ORIGINS` |
| Rate limiting | **PARTIAL** | custom per-route limiter + account lockout; no global IP limiter |
| SQL injection | **PASS** | Prisma parameterized; ML extractor uses params + identifier validation |
| ML internal auth | **PASS** | constant-time bearer token, server-side only |
| Read-only ML DB role | **BLOCKED** | `taleemplus_ml_reader` not yet created (SQL script ready) |
| **Secrets in git history** | 🔴 **FAIL** | `taleemplus_backend/.env` in `10c418d`/`ecf87a4`, reachable from `origin/main`,`origin/release/1.0.1`,+2 |

**Rotation steps (do now — old values are considered leaked):**
1. Neon: reset the DB role password; update `DATABASE_URL` in backend `.env` + Vercel env.
2. Backend: new `JWT_SECRET` and `REFRESH_TOKEN_SECRET` (`node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`).
3. (Optional, needs your approval) purge history with `git filter-repo`/BFG + force-push. Not done automatically (approval gate). Rotation is mandatory regardless.

## 9. GitHub security status — **NOT VERIFIED (needs approval / `gh`)**
- Remote: `github.com/RakibAkram5/Final_Year_Project`. Branch: `release/1.0.1`.
- Visibility (private?), branch protection, secret scanning/push protection, Dependabot, Actions permissions: **cannot be confirmed from here** and changing them is an **approval gate**.
- `.gitignore` correctly ignores `.env*` (except `.env.example`) and now the demo credentials file. **No `.env` is currently tracked.**
- Recommend (with your OK): keep repo **Private**, protect `main`, enable **secret scanning + push protection** and **Dependabot**.

## 10. License & ownership status — **PASS (docs) / PENDING (ownership)**
Created `LICENSE` (proprietary), `COPYRIGHT.md`, `OWNERSHIP.md`, `CONTRIBUTING.md`.
Ownership is **PENDING**: university IP policy + contributor names/consent must be confirmed; no sole ownership or signatures invented.

## 11. Web build status — **PASS (Local build) / deploy config required**
```
flutter build web --release  -> success (exit 0)
  build/web/main.dart.js = 5,234,500 bytes; icon fonts tree-shaken ~99%
```
- Output in `build/web/` and copied to `release/web/`.
- ⚠️ **Deployment note:** this artifact was built **without** `API_BASE_URL`; the release build intentionally throws rather than use localhost. **For a working deployment, rebuild:**
  `flutter build web --release --dart-define=API_BASE_URL=https://<your-backend>/api/v2`
- Live deployment (Netlify, per `netlify.toml`) **NOT verified** here.

## 12. APK build status — **BLOCKED**
`flutter build apk --release` not attempted: Android SDK missing `cmdline-tools` and licenses not accepted (`flutter doctor`). Fix: install Android Studio **or** cmdline-tools + set `ANDROID_HOME`, then `flutter doctor --android-licenses`.

## 13. AAB build status — **BLOCKED** (same cause as §12)

## 14. Installation test results — **NOT TESTED** (no APK produced)

## 15. End-to-end workflow results — **NOT TESTED**
Admin/Teacher/Student/Parent and ML flows require a running backend + the seeded demo
academy (ready in `prisma/seed-demo-academy.js`, pending your Neon branch). The ML
endpoints were verified locally for auth/health only.

## 16. Git commit hash — **none** (not committed; approval gate)
## 17. Git tag — **none** (proposed `v1.1.0`; approval gate). Existing tags: v1.0.1, v1.0.0.
## 18. Version information
- Current `pubspec.yaml`: `1.0.1+3`. **Proposed next: v1.1.0** (new ML/deploy features, backward compatible). Not yet applied.

## 19. SHA-256 checksums (web release artifacts)
```
main.dart.js          29f9244eb59b0e621dec31b60de6cc73a7d16fdb75a819f1912362290c4bc3d4
flutter_bootstrap.js  4eb1ea81dd39a632e7801a993139c337dcbf2a632399ab751cf622032e45709c
flutter.js            2beb1ce6b159c71540aa66030af1d7964b6a92377cc78473745e02f97b74effe
index.html            f029d6f1cd1c572d22e8e81382bbb4ccd89656596a720df1556c1b444c4b5331
```
APK/AAB checksums: **BLOCKED** (not built).

## 20. Remaining manual steps
1. 🔴 **Rotate exposed secrets** (Neon password, JWT/refresh) — §8.
2. (Approval) purge `.env` from git history; (approval) commit + tag `v1.1.0` + push.
3. Install Android cmdline-tools + accept licenses → build APK/AAB.
4. Rebuild web with `--dart-define=API_BASE_URL=...` and verify the Netlify deploy.
5. Create the read-only `taleemplus_ml_reader` role; seed the demo academy on a Neon branch.
6. Confirm GitHub: Private, branch protection, secret scanning, Dependabot.
7. Complete `OWNERSHIP.md` (university policy + contributor consent).
8. (Optional) add `express-rate-limit` for a global IP limiter.

---

### Production-readiness verdict
**Not production-ready / not fully submission-ready yet.** Strong green on code quality
(analyze clean, 114 Flutter + 53 ML + 2 Node tests pass, web builds), but blocked by:
**secret rotation (critical)**, **Android build toolchain**, **untrained ML (no real data)**,
and **unverified GitHub hardening + no approved tag/commit**. Complete the steps in §20 —
most are quick — to reach a clean, secure, tagged submission.
```
Approval still required before I: change GitHub visibility, remove collaborators,
rewrite history, push commits/tags, publish a release, deploy, run destructive DB ops,
or make ownership declarations.
```
