# Cloudflare

## Goal

Define and verify the Cloudflare edge security target state for OpenScribe docs.

## Target state

- Canonical docs origin:
  - `https://openscribe.dev/`
- Host redirect behavior:
  - `https://www.openscribe.dev/*` returns `301` to `https://openscribe.dev/$1`
- DNS model:
  - Apex `A` and `AAAA` records for GitHub Pages exist and are proxied.
  - `www` `CNAME` points to `openscribe.dev` and is proxied.
- GitHub Pages model:
  - Custom domain is `openscribe.dev`.
  - HTTPS is enforced.

## Security baseline

Cloudflare settings:

- SSL mode: `strict`
- Always Use HTTPS: `on`
- HSTS:
  - enabled: `true`
  - max age: `15552000` (180 days)
  - include subdomains: `true`
  - preload: `false`
  - nosniff: `true`

Response headers at the edge:

- `Content-Security-Policy`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), accelerometer=(), gyroscope=(), magnetometer=()`

Current enforced CSP:

```text
default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; img-src 'self' data:; script-src 'self' 'unsafe-inline' https://static.cloudflareinsights.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' https://api.github.com https://cloudflareinsights.com https://*.cloudflareinsights.com; worker-src 'self' blob:; form-action 'self'; upgrade-insecure-requests
```

## Why this is secure

- TLS is validated end to end with `strict` mode.
- HTTP is upgraded to HTTPS at the edge.
- Framing is denied to reduce clickjacking risk.
- CSP limits where scripts, styles, fonts, images, and connections can load from.
- Referrer policy reduces cross-site referrer leakage.
- Permissions policy denies browser features that docs do not require.
- DNS proxying enables Cloudflare edge controls and hides direct origin IP paths.

## Required token scope

Use an API token scoped to `openscribe.dev` with:

- `Zone: Read`
- `DNS: Edit`
- `Zone Settings: Edit`
- `Page Rules: Edit`
- `Transform Rules: Edit`
- `Zone WAF: Edit` (optional, only if WAF tuning is needed)

Expected environment variable in agent sessions:

- `SCRIBE_CLOUDFLARE_API_TOKEN`

## Read-only verification

GitHub Pages state:

```bash
gh api repos/streichsbaer/openscribe/pages
```

Cloudflare zone and settings:

```bash
CF_API="https://api.cloudflare.com/client/v4"
ZONE_ID="$(curl -sS -H "Authorization: Bearer $SCRIBE_CLOUDFLARE_API_TOKEN" \
  "$CF_API/zones?name=openscribe.dev" | jq -r '.result[0].id')"

curl -sS -H "Authorization: Bearer $SCRIBE_CLOUDFLARE_API_TOKEN" \
  "$CF_API/zones/$ZONE_ID/dns_records?per_page=200"

curl -sS -H "Authorization: Bearer $SCRIBE_CLOUDFLARE_API_TOKEN" \
  "$CF_API/zones/$ZONE_ID/settings/ssl"

curl -sS -H "Authorization: Bearer $SCRIBE_CLOUDFLARE_API_TOKEN" \
  "$CF_API/zones/$ZONE_ID/settings/always_use_https"

curl -sS -H "Authorization: Bearer $SCRIBE_CLOUDFLARE_API_TOKEN" \
  "$CF_API/zones/$ZONE_ID/settings/security_header"

curl -sS -H "Authorization: Bearer $SCRIBE_CLOUDFLARE_API_TOKEN" \
  "$CF_API/zones/$ZONE_ID/rulesets/phases/http_response_headers_transform/entrypoint"

curl -sS -H "Authorization: Bearer $SCRIBE_CLOUDFLARE_API_TOKEN" \
  "$CF_API/zones/$ZONE_ID/pagerules"
```

Public behavior and header checks:

```bash
curl -I https://openscribe.dev/
curl -I https://openscribe.dev/product/spec/
curl -I https://www.openscribe.dev/
curl -I https://streichsbaer.github.io/openscribe/
```

Pass criteria:

- `openscribe.dev` routes return `HTTP 200`.
- `www.openscribe.dev` returns `HTTP 301` to apex.
- `streichsbaer.github.io/openscribe` returns `HTTP 301` to apex.
- Security headers are present in apex responses.

Visual and console verification:

```bash
$docs-visual-review --remote-url https://openscribe.dev/ --out artifacts/docs-visual/remote-latest
```

Also run a full-route Playwright sweep from `sitemap.xml` when CSP or edge rules change.

## Change workflow

1. Confirm token scope and zone access.
2. Apply DNS and edge settings in Cloudflare.
3. Verify API state and live headers.
4. Run remote visual and console checks.
5. Record docs updates in this runbook when baseline values change.

## Related

- [Docs Verification](./docs-verification.md)
- [Release](../../site-docs/ops/release.md)
