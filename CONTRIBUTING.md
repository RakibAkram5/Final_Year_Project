# Contributing to TaleemPlus

TaleemPlus is **proprietary** (see [`LICENSE`](LICENSE)). Contributions are
accepted **only** from authorized team members and collaborators approved by the
Rights Holders (see [`OWNERSHIP.md`](OWNERSHIP.md)). By contributing, you agree
that your contribution is covered by the project license and the ownership
arrangement recorded in `OWNERSHIP.md`.

## Ground rules
- Do **not** commit secrets. No `.env`, API tokens, DB URLs, keystores or
  passwords. Use `.env.example` with placeholders only. (The repository history
  previously contained a committed `.env`; see the security notes in the final
  submission report and rotate any exposed secret.)
- Do **not** force-push to `main` or `release/*`, and do not rewrite shared history.
- Keep changes scoped; do not remove existing features to make a test pass.
- Never fake test results or API responses.

## Workflow
1. Branch from `main` (or the active `release/*` branch): `feature/<short-name>`.
2. Make focused commits with clear messages.
3. Run the relevant checks before opening a PR:
   - Flutter: `flutter analyze` and `flutter test`
   - Backend: `npm test` (needs a test Postgres; CI provides one)
   - ML service: `python -m pytest -q` (from `ml_service/`)
4. Open a Pull Request into `main`. At least one other team member reviews.
5. Do not merge with failing CI.

## Commit messages
Use concise, conventional prefixes where practical: `feat:`, `fix:`, `docs:`,
`test:`, `chore:`, `ci:`, `refactor:`.

## Security
Report a suspected secret leak or vulnerability privately to the Rights Holders —
do **not** open a public issue with details. Rotate any exposed credential first.

## Code of conduct
Be respectful and collaborative. This is a team academic project; give credit,
and keep contribution records accurate for the ownership documentation.
