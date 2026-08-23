# release/

Maintainer-only release engineering. Nothing here is deployed to end
users — `install/functions/configs.sh`'s `deploy_self` copies
`install/`, `packages/`, `system/`, `docs/`, and a few root files into
`$XDG_DATA_HOME/spacbr`; `release/` is deliberately not in that list.

## The flow

```
1. Bump VERSION, commit, git tag v0.1.0
2. release/build.sh v0.1.0     -> release/dist/{tarball, .sha256, manifest.json}
3. release/publish.sh          -> pushes the tag, creates a GitHub Release with those 3 files attached
4. spacbr.com/install redirects to release/bootstrap.sh on GitHub (see below)
```

`release/build.sh` uses `git archive`, so the tarball is exactly what
git tracks at that ref — no hand-maintained exclude list, no risk of
accidentally shipping local build artifacts or uncommitted files.

`release/publish.sh` is the one script in this repo that touches
shared/public state (pushes a tag, creates a public release). It's
never run automatically — run it yourself when a release is actually
ready, per CLAUDE.md's guidance on confirming before actions visible
to others.

## Wiring spacbr.com (§55)

The domain needs to serve four paths. None of them require hosting
real files at spacbr.com itself except `/install` — everything else
is a redirect to GitHub:

| Path | Behavior |
|---|---|
| `/install` | Redirect (302) to `https://raw.githubusercontent.com/eightharsh/spacbr/main/release/bootstrap.sh` — `curl -fsSL` follows redirects, so this works with the standard one-liner. |
| `/source` | Redirect to `https://github.com/eightharsh/spacbr` |
| `/releases` | Redirect to `https://github.com/eightharsh/spacbr/releases` |
| `/docs` | Redirect to `https://github.com/eightharsh/spacbr/tree/main/docs` |

Any static host that supports a redirects file works. For Cloudflare
Pages or Netlify, a `_redirects` file at the site root:

```
/install    https://raw.githubusercontent.com/eightharsh/spacbr/main/release/bootstrap.sh   302
/source     https://github.com/eightharsh/spacbr                                             302
/releases   https://github.com/eightharsh/spacbr/releases                                    302
/docs       https://github.com/eightharsh/spacbr/tree/main/docs                              302
```

Plain GitHub Pages doesn't support server-side redirects natively —
put Cloudflare in front of it, or use Cloudflare/Netlify Pages
directly instead. This file isn't included in this repo since it's
static-site infrastructure, not SPACBR itself — it belongs in
whatever repo/project actually backs spacbr.com.

## Why bootstrap.sh isn't versioned like everything else

`release/bootstrap.sh` lives on `main` and is expected to change
independently of tagged releases — its only job is to fetch a
specific, checksummed release and hand off to it (CLAUDE.md §54). The
thing that must stay strictly versioned is what it fetches (the
tarball + manifest), not the fetcher itself. This is the same pattern
most curl-pipe-installers use.

## What's not done yet

- No release has actually been cut — `git tag` has never been run in
  this repo.
- No GitHub remote is configured (`git remote -v` is empty).
- The actual spacbr.com hosting/DNS/redirects setup lives outside this
  repo and hasn't been done.
- GPG-signing release artifacts (§59's "signed metadata/artifacts
  where practical") isn't implemented — sha256 checksum verification
  is the current integrity mechanism. Worth adding once there's a
  signing key you're prepared to manage long-term.
