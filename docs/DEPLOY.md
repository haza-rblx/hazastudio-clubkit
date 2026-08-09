# Deploying `docs/` to Cloudflare Workers

Yes — this is a plain static site (HTML/CSS/JS, no build step), so it deploys
to **Cloudflare Workers** as a **static assets** Worker: no server code, Cloudflare
just serves the files from its edge network. This is the same approach used by
Cloudflare Pages, but configured through `wrangler.toml` like the other Workers
in this repo (`tools/donation-api`, `tools/game-data-api`).

## One-time setup

```powershell
cd docs
npm install
npx wrangler login   # opens a browser to authorize your Cloudflare account
```

## Deploy

```powershell
cd docs
npm run cf:deploy
```

This uploads everything in `docs/` (as configured by `[assets]` in
`wrangler.toml`) and prints a `*.workers.dev` URL, e.g.
`https://hazastudio-clubkit-docs.<your-subdomain>.workers.dev`.

Re-run `npm run cf:deploy` any time the docs change — there is no CI wiring in
this repo yet, so it's a manual step for now.

## Local preview

```powershell
cd docs
npm run cf:dev
```

Serves the same static-assets configuration locally before you deploy.

## Custom domain (optional)

In the Cloudflare dashboard → **Workers & Pages** → the `hazastudio-clubkit-docs`
Worker → **Settings → Domains & Routes** → **Add** → enter a subdomain you own
on a zone already on Cloudflare (e.g. `docs.hazastudio.com`). No code changes
needed.

## What's configured

| File | Purpose |
|------|---------|
| `wrangler.toml` | `name`, `compatibility_date`, and `[assets]` (serves `docs/` as-is, custom `404.html`, trailing-slash normalization) |
| `_headers` | Cache-Control + baseline security headers, read automatically by the Workers assets runtime |
| `404.html` | Themed not-found page (returned for any unmatched path) |
| `package.json` | `wrangler` devDependency + `cf:dev` / `cf:deploy` scripts |

No `main` worker script is needed — this is a pure static-assets deployment
(no API routes, no server logic). If you later want e.g. a redirect map or
an edge-side i18n default-locale redirect, add a `src/index.ts` Worker script
and reference it via `main` in `wrangler.toml`, then set `run_worker_first`.

## Alternatives

- **GitHub Pages** — free, zero Cloudflare account needed, but no edge
  caching/headers control like `_headers` gives here.
- **Cloudflare Pages** — same result, Git-connected auto-deploys on push
  instead of manual `wrangler deploy`. Worth switching to once this repo is
  pushed to GitHub and auto-deploy on merge is wanted.
