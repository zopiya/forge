---
name: ant-design
description: React admin UI via Ant Design (antd v6) — CLI-verified component APIs, ProComponents for admin dashboards/CRUD, and theming conventions
---

# Ant Design

Use this skill when building or reviewing a React admin/management console,
or any UI built on Ant Design (antd). This skill targets **antd v6 only** —
see Pinned Versions below, no v4/v5 fallback. Even within v6, antd ships
fast enough that exact prop shapes drift from training data — verify
anything beyond the pinned baseline with the `antd` CLI before writing it.

## Pinned Versions

Fixed install line, not a menu of options:

```bash
npm install antd@^6 @ant-design/icons@^6 react@^19 react-dom@^19
npm install @ant-design/pro-components@3.1.14-6
# ^ exact version, not a tag — this v6-compatible pro-components line only
# ships under the `beta` dist-tag today; `latest` is still the old v1.x/
# antd-v4 line and will silently break against antd v6. Re-check with
# `npm view @ant-design/pro-components dist-tags` before reuse — it will
# eventually promote to `latest`.
```

Every command and example below assumes this baseline. Don't downgrade to
antd v5 / pro-components v1.x-v2.x to match an older blog post, Stack
Overflow answer, or your own training data. If a project is genuinely still
on v5, that's an explicit migration task (`antd migrate 5 6`), not this
skill's default path.

## Core Commands

```bash
npx @ant-design/cli list                          # all components, versions
npx @ant-design/cli info <Component> --version 6   # props, types, defaults
npx @ant-design/cli doc <Component> --version 6    # full markdown docs
npx @ant-design/cli demo <Component> [name]        # runnable demo source
npx @ant-design/cli token [Component]              # design token values
npx @ant-design/cli changelog 5 6 [Component]      # API diff across versions
npx @ant-design/cli lint ./src                     # deprecated API usage
npx @ant-design/cli migrate 5 6                    # v5→v6 migration checklist
npx @ant-design/cli usage ./src                    # import/component stats
npx @ant-design/cli doctor                         # env/config diagnostics
```

Install globally (`npm i -g @ant-design/cli`) if querying repeatedly in one
session — `npx` re-resolves every call.

Always query before writing an unfamiliar prop — `antd info <Component>
--version 6` — instead of guessing from memory. Pass `--version 6`
explicitly rather than relying on auto-detect, unless the project is a
confirmed pre-existing v5 codebase.

## Scaffolding a New Admin App

Two paths, both on the Pinned Versions baseline — pick based on what
already exists, don't ask by default:

- **Extend an existing app** (default): Vite + React 19 + TS, install the
  Pinned Versions packages into it directly. Extend the existing framework,
  don't re-scaffold around it.
- **Genuine greenfield, batteries-included**: clone the official
  `ant-design-pro` repo (see Common Layouts) — its `master` branch already
  sits on this exact baseline (antd ^6.5.1, pro-components ^3.1.14-2, React
  ^19.2.7), so it doubles as scaffold and page-template reference. Trade-off:
  locks into Umi Max's routing/build conventions — a deliberate choice, not
  a default.

Either way: `ProLayout` for the shell/nav, `ProTable` for CRUD list+search+
pagination, `ProForm`/`ModalForm` for create/edit, `ProDescriptions` for
detail views — don't hand-roll what ProComponents already solves.

## Theming

`ConfigProvider` + `theme.algorithm` (`defaultAlgorithm`/`darkAlgorithm`/
`compactAlgorithm`, composable). Source token overrides from `design.md`
(`npx @ant-design/cli design.md` or `https://ant.design/design.md`) rather
than memorized hex values — it's the canonical machine-readable theme spec:
color tokens, typography scale, spacing/radius. For a single component's
token names, `npx @ant-design/cli token <Component>`.

## Common Layouts & Page Templates

Don't hand-roll page structure from scratch. `ant-design-pro`
(`https://github.com/ant-design/ant-design-pro`, `master` branch, confirmed
on this skill's Pinned Versions baseline) is the always-current reference
gallery — clone it shallow
(`git clone --depth=1 https://github.com/ant-design/ant-design-pro.git /tmp/antd-pro-ref`)
and read the matching page under `src/pages/`. Copy the structure, not
verbatim code, and re-verify props via `antd doc`/`antd demo` before
trusting it wholesale — its pinned ranges move independently of whatever
project you're building.

| Need | Building blocks | Reference page in `ant-design-pro` |
|---|---|---|
| Layout shell (side/top/mixed nav) | `ProLayout` | — |
| List / search-table | `ProTable` | `List / Table List` |
| Create / edit form | `ProForm` / `ModalForm` / `DrawerForm` / `StepsForm` | `Form / Basic Form`, `Form / Step Form` |
| Detail / profile view | `ProDescriptions` / `ProCard` tabs | `Profile / Basic`, `Profile / Advanced` |
| Dashboard / overview | `StatisticCard` + `@ant-design/charts` | `Dashboard / Analysis`, `Dashboard / Workplace` |
| Settings / config management | grouped `ProForm` sections + side tabs | `Account / Settings` |
| Login / auth | `LoginForm` / `LoginFormPage` | `User / Login` |
| Exceptions / results | antd `Result` | `Exception` (403/404/500), `Result` |

Minimal structural sketches (not copy-paste-ready — confirm exact props via
`antd demo ProLayout basic` / `antd demo ProTable basic` first):

```tsx
// Shell
<ProLayout route={routeConfig} menuDataRender={getMenu}>
  <PageContainer>{children}</PageContainer>
</ProLayout>

// List page
<ProTable
  columns={columns}
  request={async (params) => fetchList(params)}
  rowKey="id"
  search={{ labelWidth: 'auto' }}
  toolBarRender={() => [<Button key="new">New</Button>]}
/>
```

## Avoid

- Reaching for v4/v5 API shapes, prop names, or import paths from memory or
  older posts — Pinned Versions v6 baseline only, no straddling majors.
- Hand-rolling table/form/layout that ProComponents already solves.
- Hardcoding color hex values instead of theme tokens.
- Skipping `antd lint` after any version change.
- Copying an `ant-design-pro` reference page verbatim without a quick
  re-check against the pinned baseline.

## Review Checklist

- Dependencies match Pinned Versions (antd v6 line, no v5 packages sneaked
  in via a transitive/copy-paste install).
- Props/APIs verified against `antd info`/`doc --version 6`.
- Theme values come from tokens/`design.md`, not hardcoded.
- No hand-rolled table/form duplicating ProComponents.
- `antd lint` clean.
