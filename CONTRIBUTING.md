# Contributing to OpenPaw

Thank you for considering a contribution to OpenPaw. Please read this guide before submitting
issues or pull requests.

---

## Contributor License Agreement (CLA)

**All contributors must sign the CLA before their pull request can be merged.**

OpenPaw uses a dual-license model: the open-source release is under AGPLv3, and a separate
commercial license covers the hosted cloud service. The CLA grants the project maintainer the
right to distribute your contribution under both licenses.

### How to sign

Add the following line to your pull request description (a one-time statement per PR is
sufficient; you do not need to add it to every commit):

```
I have read and agree to the OpenPaw CLA.
```

The full text of the CLA is in [`CLA.md`](./CLA.md). By including the statement above you
confirm all representations in Section 4 are true.

Pull requests without this statement will not be merged. If you forget, a maintainer will
remind you with a comment.

---

## What We Welcome

- Bug fixes with a clear description of the problem and the fix
- Performance improvements with measurable before/after data
- Documentation corrections and clarifications
- New adapter implementations (LLM providers, storage, etc.)
- Test coverage improvements

Before starting significant new features, open an issue first to discuss the approach.
This avoids wasted effort if the feature doesn't fit the project's current direction.

---

## Development Setup

```bash
# Install dependencies
make install

# Run all checks
make lint
make typecheck
make test

# Run locally (Pi / local-only mode)
make dev-pi
```

See `Makefile` for the full list of available targets.

---

## Pull Request Guidelines

1. **Branch from `main`** and keep your branch up to date.
2. **One concern per PR.** Split unrelated changes into separate pull requests.
3. **Include the CLA sign-off** in the PR description (see above).
4. **Pass all checks** — linting (`ruff`), type checking (`mypy`), and tests must be green.
5. **Do not break contracts** — changes to `contracts/events/v0.json` or
   `contracts/commands/v0.json` require explicit discussion. See `contracts/README.md`.
6. **Follow naming conventions** in `docs/naming-conventions.md`.

---

## Reporting Issues

- Search existing issues before opening a new one.
- For security vulnerabilities, do **not** open a public issue. Contact the maintainer directly.
- Include steps to reproduce, expected behaviour, and actual behaviour.

---

## License

By contributing, you agree that your contributions will be licensed as described in
[`CLA.md`](./CLA.md) and that the project is distributed under the
[GNU Affero General Public License v3](./LICENSE).
