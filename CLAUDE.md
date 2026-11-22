# Eager Platform

Public library of reusable GitHub Actions workflows and Bicep modules for a small family of personal
apps on Azure: a static web front end, a .NET Function App API, and PostgreSQL, deployed with OIDC and
deployment stacks. The full design lives in the app repos (`docs/blueprint.md`).

**This repo is public, and so are its run logs.** It must never contain secrets, tenant, subscription or
object IDs, email addresses, resource names, or anything else specific to one tenant. Those live in the
private ops repo and the app repos, and reach these workflows as inputs. Its own pipeline (`ci.yml`) only compiles and lints; it never
signs in to Azure, and nothing here deploys.

## Layout

- `.github/workflows/reusable-*.yml`: called by app repos as `OWNER/platform/.github/workflows/<file>@v1`.
- `.github/workflows/ci.yml`: compiles every module and runs actionlint on PRs and pushes.
- `bicep/modules/`: building blocks that app repos check out at the pinned tag into `.platform/`.

## Rules

- **Versioning is a contract.** App repos pin `@v1`. Within v1, only add optional inputs and outputs;
  never rename, remove or change the meaning of one. Breaking changes go to `v2`. Tag every release
  (`v1.0.0`, `v1.1.0` …); Jay alone moves the floating `v1` tag.
- Validate before saying done: `az bicep build` for every changed module and `actionlint` for every workflow.
- A workflow here must take everything tenant-specific as inputs from its caller.
- Same "ask first" list as the other repos: no GitHub settings change, push or tag without Jay's approval.
