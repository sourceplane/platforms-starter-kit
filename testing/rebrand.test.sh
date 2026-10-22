#!/usr/bin/env bash
# THE REBRAND WRITES EACH VALUE ONCE, AND WHAT IT WROTE STAYS WRITTEN.
#
# Drives the real tooling/rebrand/rebrand.mjs over one-file trees and compares
# the file. Each case is a shape this baseline's identity actually takes in the
# tree — the site-name seam, the worker name in the component and the
# wrangler config, the KV namespace titles and the terraform `repo` they are
# built from, the root domain tenants hang off (prod's, stage's below it, the
# wildcard route the owner adds), a secret ref, a link to the source
# repository — and the survival cases run through three passes, so a value
# an earlier rebrand wrote (a re-run phase re-runs the rebrand over
# everything placed) comes out of every later one unchanged.
#
# The identity is PINNED (fixtures/baseline-identity.platforms-starter-kit.json)
# rather than read from .baseline/identity.json: what this tests is the engine,
# and its fixtures spell the identity out literally.
#
# Needs: node, git. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rebrand="$here/../tooling/rebrand/rebrand.mjs"
identity="$here/fixtures/baseline-identity.platforms-starter-kit.json"

fail=0
# check NAME VALUES-JSON FILE CONTENT WANT [PASSES]
check() {
  local name="$1" values="$2" file="$3" content="$4" want="$5" passes="${6:-1}"
  local tmp got out i
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  for ((i = 1; i <= passes; i++)); do
    git -C "$tmp" add -A
    if ! out="$(cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty 2>&1)"; then
      echo "   ✕  $name: rebrand pass $i failed:" >&2
      printf '%s\n' "$out" | sed 's/^/        /' >&2
      fail=1
      rm -rf "$tmp"
      return
    fi
  done
  got="$(cat "$tmp/$file")"
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then
    echo "   ok  $name"
  else
    echo "   ✕  $name:" >&2
    echo "        got:  $got" >&2
    echo "        want: $want" >&2
    fail=1
  fi
}

acme='{"reponame":"acme-tenants","productname":"Acme Tenants","productdomain":"tenants.acme.dev","githuborg":"acme-inc","subdomain":"acme","orunWorkspace":"ws_79BDXAZQ"}'

echo "── rebrand: the site's own identity"
check "the site-name seam takes the product's name" \
  "$acme" apps/web/app/site.ts 'export const SITE_NAME = "Platforms Starter Kit";' \
  'export const SITE_NAME = "Acme Tenants";'
check "…and stays a valid string for a name with an apostrophe and an ampersand" \
  '{"reponame":"sams-tenants","productname":"Sam'"'"'s Tenants & Co","productdomain":"sam.dev"}' \
  apps/web/app/site.ts 'export const SITE_NAME = "Platforms Starter Kit";' \
  'export const SITE_NAME = "Sam'"'"'s Tenants & Co";'
check "the display name elsewhere is content, and is left alone" \
  "$acme" apps/web/README.md "from Vercel's Platforms Starter Kit, the Platforms Starter Kit." \
  "from Vercel's Platforms Starter Kit, the Platforms Starter Kit."
check "the worker name is re-prefixed, the environment suffix kept" \
  "$acme" apps/web/component.yaml 'workerName: platforms-starter-kit-web' \
  'workerName: acme-tenants-web'
check "the wrangler config's worker name, template and render alike" \
  "$acme" apps/web/wrangler.template.jsonc '  "name": "platforms-starter-kit-web",' \
  '  "name": "acme-tenants-web",'
check "the environment URLs: worker name and subdomain" \
  "$acme" intent.yaml '    url: https://platforms-starter-kit-web-stage.your-workers-subdomain.workers.dev' \
  '    url: https://acme-tenants-web-stage.acme.workers.dev'
check "the KV namespace's terraform repo — every namespace title is built on it" \
  "$acme" infra/terraform/cloudflare-kv/terraform/main.tf '  default = "platforms-starter-kit"' \
  '  default = "acme-tenants"'
check "the per-environment terraform repo parameter" \
  "$acme" intent.yaml '        repo: platforms-starter-kit' \
  '        repo: acme-tenants'
check "a fixture's namespace title follows the same rule" \
  "$acme" apps/web/wiring.fixture.json '    "app_kv_title": "stg-platforms-starter-kit-app-kv-stage"' \
  '    "app_kv_title": "stg-acme-tenants-app-kv-stage"'
check "the root domain tenants hang off is the product's domain, not a renamed slug" \
  "$acme" intent.yaml '      BASE_DOMAIN: platforms-starter-kit.example.com' \
  '      BASE_DOMAIN: tenants.acme.dev'
check "stage's root domain stays one level below it" \
  "$acme" intent.yaml '      BASE_DOMAIN: stage.platforms-starter-kit.example.com' \
  '      BASE_DOMAIN: stage.tenants.acme.dev'
check "no domain given: the reserved placeholder, for an owner to replace later" \
  '{"reponame":"acme-tenants","productname":"Acme Tenants","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: platforms-starter-kit.example.com' \
  '      BASE_DOMAIN: acme-tenants.example.com'
check "…and stage's root domain one level below it" \
  '{"reponame":"acme-tenants","productname":"Acme Tenants","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: stage.platforms-starter-kit.example.com' \
  '      BASE_DOMAIN: stage.acme-tenants.example.com'
check "an empty domain is no domain" \
  '{"reponame":"acme-tenants","productname":"Acme Tenants","productdomain":""}' \
  intent.yaml '      BASE_DOMAIN: platforms-starter-kit.example.com' \
  '      BASE_DOMAIN: acme-tenants.example.com'
check "the wildcard route the owner adds names the product's domain and Worker" \
  "$acme" README.md '`*.platforms-starter-kit.example.com/*` → `platforms-starter-kit-web-prod`' \
  '`*.tenants.acme.dev/*` → `acme-tenants-web-prod`'
check "the repo slug" \
  "$acme" package.json '  "name": "platforms-starter-kit",' \
  '  "name": "acme-tenants",'
check "a wiring secret ref names the product's workspace and project" \
  "$acme" apps/web/component.yaml \
  '    WIRING_CLOUDFLARE_KV_STAGE: "secret://platforms-starter-kit/platforms-starter-kit/stage/WIRING_CLOUDFLARE_KV"' \
  '    WIRING_CLOUDFLARE_KV_STAGE: "secret://ws_79BDXAZQ/acme-tenants/stage/WIRING_CLOUDFLARE_KV"'
check "a templated provider secret ref too" \
  "$acme" infra/terraform/cloudflare-kv/component.yaml \
  '    CLOUDFLARE_API_TOKEN: "secret://platforms-starter-kit/platforms-starter-kit/{{ .environment }}/CLOUDFLARE_API_TOKEN"' \
  '    CLOUDFLARE_API_TOKEN: "secret://ws_79BDXAZQ/acme-tenants/{{ .environment }}/CLOUDFLARE_API_TOKEN"'
check "a link to the source repository names the product's owner and repository" \
  "$acme" README.md 'See https://github.com/sourceplane/platforms-starter-kit for the source.' \
  'See https://github.com/acme-inc/acme-tenants for the source.'
check "…and without githuborg keeps the baseline's owner" \
  '{"reponame":"acme-tenants","productname":"Acme Tenants","productdomain":"tenants.acme.dev"}' \
  README.md 'See https://github.com/sourceplane/platforms-starter-kit for the source.' \
  'See https://github.com/sourceplane/acme-tenants for the source.'
check "the upstream template's own repository is not this one, and is left alone" \
  "$acme" README.md 'From https://github.com/vercel/platforms.' \
  'From https://github.com/vercel/platforms.'
check "org-owned identity is not renamed" \
  "$acme" intent.yaml 'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai' \
  'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai'

echo "── rebrand: a written value is not rewritten, in any later pass"
contains='{"reponame":"platforms-starter-kit-2","productname":"Platforms Starter Kit 2","productdomain":"platforms-starter-kit.example.com.au","githuborg":"sourceplane","subdomain":"your-workers-subdomain-2"}'
check "a repo slug containing the baseline's slug survives three passes" \
  "$contains" package.json '  "name": "platforms-starter-kit",' \
  '  "name": "platforms-starter-kit-2",' 3
check "a worker name built on it survives three passes" \
  "$contains" apps/web/component.yaml 'workerName: platforms-starter-kit-web' \
  'workerName: platforms-starter-kit-2-web' 3
check "a namespace title built on it survives three passes" \
  "$contains" apps/web/wiring.fixture.json '"app_kv_title": "prod-platforms-starter-kit-app-kv-prod"' \
  '"app_kv_title": "prod-platforms-starter-kit-2-app-kv-prod"' 3
check "a domain containing the baseline's domain survives three passes" \
  "$contains" intent.yaml 'BASE_DOMAIN: platforms-starter-kit.example.com' \
  'BASE_DOMAIN: platforms-starter-kit.example.com.au' 3
check "…and stage's, below it" \
  "$contains" intent.yaml 'BASE_DOMAIN: stage.platforms-starter-kit.example.com' \
  'BASE_DOMAIN: stage.platforms-starter-kit.example.com.au' 3
check "a subdomain containing the placeholder survives three passes" \
  "$contains" apps/web/component.yaml 'workersDevSubdomain: your-workers-subdomain' \
  'workersDevSubdomain: your-workers-subdomain-2' 3
check "a site name containing the baseline's name survives three passes" \
  "$contains" apps/web/app/site.ts 'export const SITE_NAME = "Platforms Starter Kit";' \
  'export const SITE_NAME = "Platforms Starter Kit 2";' 3

# --verify runs in every phase. Without the product's values it cannot tell
# the product's own identity from a leftover; with them it can. A real
# leftover must fail it either way.
verify() { # NAME VALUES FILE CONTENT WANT(pass|fail) [--values]
  local name="$1" values="$2" file="$3" content="$4" want="$5" withvalues="${6:-}" tmp got
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  git -C "$tmp" add -A
  if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --verify ${withvalues:+--values .rebrand/values.json} >/dev/null 2>&1); then got=pass; else got=fail; fi
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then echo "   ok  $name"; else echo "   ✕  $name: --verify ${got}ed, want $want" >&2; fail=1; fi
}
echo "── rebrand --verify: the product's own identity is not residue"
verify "given the values, a slug containing the baseline's passes" \
  "$contains" package.json '"name": "platforms-starter-kit-2"' pass --values
verify "without them it cannot know, and fails" \
  "$contains" package.json '"name": "platforms-starter-kit-2"' fail
verify "given the values, a real leftover still fails" \
  "$acme" package.json '"name": "platforms-starter-kit"' fail --values
verify "a leftover worker name fails" \
  "$acme" apps/web/wrangler.jsonc '"name": "platforms-starter-kit-web",' fail --values
verify "a leftover namespace title fails" \
  "$acme" apps/web/wiring.fixture.json '"app_kv_title": "stg-platforms-starter-kit-app-kv-stage"' fail --values
verify "a leftover root domain fails" \
  "$acme" intent.yaml 'BASE_DOMAIN: stage.platforms-starter-kit.example.com' fail --values
verify "a leftover code identifier fails (no rule renames it — so nothing may spell it)" \
  "$acme" apps/web/app/x.ts 'export class PlatformsStarterKit {}' fail --values
verify "a clean product passes" \
  "$acme" package.json '"name": "acme-tenants"' pass --values

echo "── rebrand: a residue it cannot rename fails the rebrand itself"
tmp="$(mktemp -d)"; git -C "$tmp" init -q; mkdir -p "$tmp/.rebrand" "$tmp/apps/web"
printf '%s\n' "$acme" > "$tmp/.rebrand/values.json"
printf 'const x = "PLATFORMS_STARTER_KIT_TOKEN"\n' > "$tmp/apps/web/x.ts"
git -C "$tmp" add -A
if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty >/dev/null 2>&1); then
  echo "   ✕  an unrenamable env-var prefix passed the rebrand" >&2; fail=1
else
  echo "   ok  an unrenamable env-var prefix fails the rebrand, naming the file"
fi
rm -rf "$tmp"

[ "$fail" -eq 0 ] || exit 1
echo "rebrand.test.sh: ok"
