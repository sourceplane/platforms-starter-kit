#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, deploys (dry) and serves.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its one pull request merges),
#      run what `checks.yml` runs on that PR — install with the lockfile the
#      phase confirmed, render the wrangler fixture and check the committed
#      config IS that render, typecheck, lint, test, build. The landing WAITS
#      on those checks, so a product they refuse is a bootstrap that never
#      merges;
#   2. the stage lane's own steps, rendered by `orun plan` in the product for
#      a pull request (the verify profile: the deploy profile has no dry run)
#      — `verify-app-structure` (which checks the wrangler config exists
#      BEFORE anything is built), `build-app` (the component's buildCommand:
#      the live wiring render, then the build), `verify-build-output` and
#      `deploy-dry-run` (`wrangler deploy --dry-run --name <reponame>-web-stage`).
#      They run IN THE TREE THE RUNNER STAGES for the job
#      (testing/lib/stage-job.py), with the dependency layout the pinned
#      composition produces, and with the stage wiring document in the job's
#      environment as the platform resolves it (the component's secretEnv) —
#      so the namespace id in the built config is asserted to be the
#      document's, not the fixture's;
#   3. serve the built Worker with `wrangler dev` and run the component's OWN
#      `smokeCommand` against it, verbatim — the check the real deploy ends
#      with — and then every route the site promises, the way a fresh deploy
#      on workers.dev is used: the landing page carries the product's name
#      and offers tenants at `<host>/s/<name>` (127.0.0.1 is, like
#      workers.dev, off the root domain); a tenant is CREATED through the
#      landing form exactly as a browser without JavaScript submits it (the
#      server action writes the KV binding; wrangler dev provides the
#      namespace locally) and redirected to `/s/<name>`; it is READ BACK
#      through the Worker on its page, on `/admin`, and by the action
#      refusing it a second time; the same tenant answers as a subdomain of
#      the stage root domain once a request arrives on it (the custom-domain
#      future, by Host header), `/admin` stays off tenant hosts, unknown
#      tenants and paths are 404s, the static assets are served — and the
#      tenant is deleted from `/admin` and is gone.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare token, apply the namespace, deploy for real and probe
# workers.dev — or attach a domain. The KV root is verified to `terraform
# validate` and its plan is part of every pull request's lanes; the apply
# needs an account.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, and the network for
# `pnpm install` and the build's Google Font (or a warm store). A few minutes:
# two installs and builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
cleanup() {
  if [ -n "$dev_pid" ]; then
    kill -TERM -- "-$dev_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$dev_pid" 2>/dev/null || break; sleep 0.5; done
    kill -KILL -- "-$dev_pid" 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false NEXT_TELEMETRY_DISABLED=1 TURBO_TELEMETRY_DISABLED=1

# What checks.yml runs, step for step, read out of the workflow the product
# carries so the two cannot drift: every `run:` of its one job, in order.
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  while IFS= read -r cmd; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done < <(python3 - "$dir/.github/workflows/checks.yml" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for job in wf["jobs"].values():
    for step in job["steps"]:
        if "run" in step:
            print(step["run"].strip())
PY
)
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"
s01="$(git -C "$tree" rev-parse HEAD~1)"

# ── 1. the product's one pull request ──────────────────────────────────────
echo "── 01-product's landing, under the checks its PR waits on"
git -C "$tree" worktree add -q "$scratch/at-01" "$s01"
checks "$scratch/at-01" "$scratch/checks-01.log"
# The first Checks build is done; its tree is not needed again, and the disk is shared.
git -C "$tree" worktree remove --force "$scratch/at-01"

# ── 2. the stage lane's steps, in the job's own tree ──────────────────────
echo "── the stage lane: verify-app-structure, build-app, verify-build-output, deploy-dry-run"
# A pull request that changes the app: the lane `orun plan` gives it.
git -C "$tree" checkout -q -b e2e-pr
echo "<!-- a change to the app's component -->" >> "$tree/apps/web/README.md"
git -C "$tree" -c user.email=e2e@example.invalid -c user.name=e2e commit -qam "a pull request"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base main --head HEAD --env stage --output "$scratch/plan.json") > "$scratch/plan.log" 2>&1 \
  || { echo "FAIL: orun plan" >&2; tail -15 "$scratch/plan.log" >&2; exit 1; }
python3 - "$scratch/plan.json" "$scratch/steps" <<'PY'
import json, pathlib, sys
plan = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2]); out.mkdir()
job = next(j for j in plan["jobs"] if j["component"] == "web" and j["environment"] == "stage")
for s in job["steps"]:
    if s["id"] in ("verify-app-structure", "build-app", "verify-build-output", "deploy-dry-run"):
        (out / f"{s['id']}.sh").write_text(s.get("run") or "")
    if s["id"] == "install-workspace-dependencies":
        (out / "install.sh").write_text(s.get("run") or "")
        (out / "install.wd").write_text(s.get("working-directory") or ".")
        (out / "install.scope").write_text(s.get("scope") or "job")
(out / "path").write_text(job.get("path") or "apps/web")
for k, v in (job.get("env") or {}).items():
    (out / "env").open("a").write(f"export {k}={json.dumps(v)}\n")
(out / "secrets").write_text("\n".join(r["asEnv"] for r in job.get("secretRefs") or []))
PY
# The job's private tree, staged as orun stages it. The source checkout
# carries no build output (nothing was built in it), and its dependencies are
# what the pinned composition says: a lane-scoped install ran once in the
# source tree and is linked in, or the job installs its own.
work="$tree/.orun/runs/e2e/web.stage.verify-deploy/work"
[ -f "$scratch/steps/install.sh" ] || { echo "FAIL: the stage lane has no install step" >&2; exit 1; }
if [ "$(cat "$scratch/steps/install.scope")" = lane ]; then
  (cd "$tree" && bash -e "$scratch/steps/install.sh") > "$scratch/install.log" 2>&1 \
    || { echo "FAIL: the lane's install step" >&2; tail -30 "$scratch/install.log" >&2; exit 1; }
  python3 "$here/lib/stage-job.py" "$tree" "$work" --shared-deps
  [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; exit 1; }
  echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: lane — node_modules → the source tree's"
else
  python3 "$here/lib/stage-job.py" "$tree" "$work"
  echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: job — installing inside it"
  echo "   ▸ install-workspace-dependencies"
  (cd "$work/$(cat "$scratch/steps/path")/$(cat "$scratch/steps/install.wd")" && bash -e "$scratch/steps/install.sh") \
    > "$scratch/install.log" 2>&1 || { echo "FAIL: the lane's install step" >&2; tail -30 "$scratch/install.log" >&2; exit 1; }
  [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ] \
    || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
fi
[ ! -e "$work/apps/web/.open-next" ] || { echo "FAIL: the staged tree carries build output" >&2; exit 1; }
# What the platform resolves into the job before its first step: the wiring
# documents the KV root lease-published (the component's secretEnv). Ids no
# fixture carries, so the built config proves which one it was rendered from.
for env in stage prod; do
  key="WIRING_CLOUDFLARE_KV_$(echo "$env" | tr a-z A-Z)"
  grep -qx "$key" "$scratch/steps/secrets" || { echo "FAIL: the stage lane does not resolve $key" >&2; exit 1; }
done
export WIRING_CLOUDFLARE_KV_STAGE='{"app_kv_id":"5ca1ab1e5ca1ab1e5ca1ab1e0000a001","app_kv_title":"stg-'"$repo"'-app-kv-stage"}'
export WIRING_CLOUDFLARE_KV_PROD='{"app_kv_id":"5ca1ab1e5ca1ab1e5ca1ab1e0000a003","app_kv_title":"prod-'"$repo"'-app-kv-prod"}'
for step in verify-app-structure build-app verify-build-output deploy-dry-run; do
  [ -f "$scratch/steps/$step.sh" ] || { echo "FAIL: the stage verify lane has no $step step" >&2; exit 1; }
  echo "   ▸ $step"
  # The runner's per-job environment: the job's env (intent environment
  # `env:`), its resolved secrets, and ORUN_ENVIRONMENT; the step runs in the
  # component's directory.
  if ! (cd "$work/$(cat "$scratch/steps/path")" && \
        { [ -f "$scratch/steps/env" ] && source "$scratch/steps/env"; true; } && \
        export ORUN_ENVIRONMENT=stage && bash -e "$scratch/steps/$step.sh") > "$scratch/$step.log" 2>&1; then
    echo "FAIL: the deploy lane's $step step" >&2; tail -40 "$scratch/$step.log" >&2; exit 1
  fi
done
grep -q '"5ca1ab1e5ca1ab1e5ca1ab1e0000a001"' "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: the lane's build did not render the stage namespace id from its wiring document" >&2; exit 1; }
grep -Eq 'env\.KV\b' "$scratch/deploy-dry-run.log" && grep -q '5ca1ab1e5ca1ab1e5ca1ab1e0000a001' "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind KV to the stage namespace" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
# The build inlined the stage root domain (the job's BASE_DOMAIN, from intent.yaml).
domain="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['productdomain'])" "$values")"
grep -rqF "stage.$domain" "$work/apps/web/.open-next/server-functions" \
  || { echo "FAIL: the stage build did not inline its root domain stage.$domain" >&2; exit 1; }
echo "   the built config binds KV to the stage document's namespace id, and the build carries"
echo "   the stage root domain stage.$domain; the dry run accepts it"

# ── 3. serve it, and smoke it as the deploy does ───────────────────────────
echo "── wrangler dev over the built Worker"
port=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
(cd "$work/apps/web" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
   --name "$repo-web-stage" --show-interactive-dev-session=false) > "$scratch/dev.log" 2>&1 < /dev/null &
dev_pid=$!
url="http://127.0.0.1:$port"
for _ in $(seq 1 90); do
  curl -s -o /dev/null "$url/favicon.ico" && break
  kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
  sleep 1
done
curl -s -o /dev/null "$url/favicon.ico" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the app" >&2; exit 1; }

echo "   ▸ every route the site promises: create a tenant, and read it back through the Worker"
python3 - "$url" "$values" <<'PY'
import html, json, re, sys, urllib.error, urllib.parse, urllib.request, uuid
base, values = sys.argv[1], json.load(open(sys.argv[2]))
name, domain = values["productname"], values["productdomain"]
host = urllib.parse.urlsplit(base).netloc          # 127.0.0.1:<port> — off the root domain, like workers.dev
port = urllib.parse.urlsplit(base).port
root = f"stage.{domain}"                           # the stage build's BASE_DOMAIN
problems = []
def bad(m): problems.append(m)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None
opener = urllib.request.build_opener(NoRedirect)
def request(path, data=None, headers=None, as_host=None):
    h = dict(headers or {})
    if as_host:
        h["Host"] = f"{as_host}:{port}"
    req = urllib.request.Request(base + path, data=data, headers=h, method="POST" if data else "GET")
    try:
        with opener.open(req, timeout=30) as r:
            return r.status, r.headers, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode(errors="replace")
def text(fragment):
    return html.unescape(re.sub(r"<!-- -->|<[^>]+>", "", fragment)).strip()
def title(page):
    m = re.search(r"<title>(.*?)</title>", page, re.S)
    return html.unescape(m.group(1)) if m else None
def h1(page):
    m = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
    return text(m.group(1)) if m else None
def submit(page, path, fields):
    """POST the page's first server-action form as a browser without JavaScript
    does: its hidden $ACTION_* inputs, plus the given fields, multipart."""
    form = re.search(r'<form[^>]*method="POST"[^>]*>(.*?)</form>', page, re.S)
    if not form:
        return None
    hidden = []
    for m in re.finditer(r"<input([^>]*)/?>", form.group(1)):
        attrs = dict(re.findall(r'([\w$:-]+)="([^"]*)"', m.group(1)))
        n = html.unescape(attrs.get("name", ""))
        if n.startswith("$ACTION") and attrs.get("type") == "hidden":
            hidden.append((n, html.unescape(attrs.get("value", ""))))
    if not hidden:
        return None
    b = "----e2e" + uuid.uuid4().hex
    body = b"".join(f'--{b}\r\nContent-Disposition: form-data; name="{n}"\r\n\r\n{v}\r\n'.encode()
                    for n, v in hidden + list(fields)) + f"--{b}--\r\n".encode()
    return request(path, data=body, headers={"Content-Type": f"multipart/form-data; boundary={b}", "Origin": base})

# ── the landing page, off the root domain ─────────────────────────────────
status, _, page = request("/")
if status != 200:
    bad(f"/ answered {status}")
if title(page) != name:
    bad(f"the landing page's <title> is {title(page)!r}, not {name!r}")
if name not in [text(p) for p in re.findall(r"<p[^>]*>(.*?)</p>", page, re.S)]:
    bad(f"the landing page does not name the site {name!r}")
if h1(page) != host:
    bad(f"the landing page's heading is {h1(page)!r} — off the root domain it is the host asked on, {host}")
if f"Opens at {host}/s/your-subdomain" not in page:
    bad("the landing form does not offer tenants at <host>/s/<name> — the workers.dev fallback")
if f"until {root}'s wildcard route" not in html.unescape(page):
    bad(f"the landing page does not say tenant subdomains of {root} need its wildcard route")
if "platforms-starter-kit" in page or "Platforms Starter Kit" in page:
    bad("the landing page still carries the baseline's name")

# ── create a tenant through the form, as a browser without JavaScript ─────
tenant, emoji = "acme-e2e", "🚀"
created = submit(page, "/", [("subdomain", tenant), ("icon", emoji)])
if not created:
    bad("the landing page has no server-action form to submit")
else:
    s, h, _ = created
    if s not in (303, 307) or h.get("location") != f"/s/{tenant}":
        bad(f"creating {tenant} answered {s} → {h.get('location')!r}; want a redirect to /s/{tenant} on this host")

# ── read it back through the Worker ───────────────────────────────────────
status, _, page = request(f"/s/{tenant}")
if status != 200 or emoji not in page:
    bad(f"/s/{tenant} answered {status}{'' if emoji in page else ' without the emoji'} — the tenant was not read back")
if h1(page) != f"Welcome to {host}/s/{tenant}" or title(page) != f"{host}/s/{tenant}":
    bad(f"/s/{tenant} says {h1(page)!r} / <title> {title(page)!r} — its address on this host is {host}/s/{tenant}")
status, _, admin = request("/admin")
if status != 200 or f'href="/s/{tenant}"' not in admin or emoji not in admin:
    bad(f"/admin answered {status} and does not list {tenant} linking /s/{tenant}")
again = submit(request("/")[2], "/", [("subdomain", tenant), ("icon", "🐙")])
if not again or again[0] != 200 or "This subdomain is already taken" not in again[2]:
    bad(f"creating {tenant} a second time was not refused from the stored record: {again and again[0]}")

# ── the same tenant on the root domain, as after the custom-domain step ───
status, _, page = request("/", as_host=f"{tenant}.{root}")
if status != 200 or emoji not in page or h1(page) != f"Welcome to {tenant}.{root}":
    bad(f"{tenant}.{root}/ answered {status} with {h1(page)!r} — the subdomain rewrite to the tenant page")
status, h, _ = request("/admin", as_host=f"{tenant}.{root}")
at = f"http://{tenant}.{root}:{port}"
if status not in (307, 308) or urllib.parse.urljoin(f"{at}/admin", h.get("location") or "") != f"{at}/":
    bad(f"/admin on a tenant host answered {status} → {h.get('location')!r}; want a redirect to that host's /")
status, _, page = request("/", as_host=root)
if status != 200 or h1(page) != root or f".{root}" not in text(page) or "Opens at" in page:
    bad(f"{root}/ answered {status} with {h1(page)!r} — on the root domain tenants are <name>.{root}")
for as_host, path in ((f"nobody-e2e.{root}", "/"), (None, "/s/nobody-e2e")):
    status, _, _ = request(path, as_host=as_host)
    if status != 404:
        bad(f"an unknown tenant ({as_host or ''}{path}) answered {status}, not 404")

# ── static assets, an unknown path ────────────────────────────────────────
for path, want, ctype in (("/favicon.ico", 200, "image/"), ("/no-such-page", 404, "text/html")):
    s, h, _ = request(path)
    if s != want or not (h.get("content-type") or "").startswith(ctype):
        bad(f"{path} answered {s} {h.get('content-type')}, want {want} {ctype}")

# ── delete it from /admin, as a browser without JavaScript ────────────────
deleted = submit(admin, "/admin", [("subdomain", tenant)])
if not deleted or deleted[0] != 200:
    bad(f"deleting {tenant} from /admin answered {deleted and deleted[0]}")
status, _, _ = request(f"/s/{tenant}")
if status != 404:
    bad(f"/s/{tenant} answered {status} after the delete, not 404")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   / (the product's name; tenants offered at {host}/s/<name>); {tenant} created by the landing form,")
print(f"   read back on /s/{tenant}, on /admin and by a refused duplicate; {tenant}.{root} served as a")
print(f"   subdomain; /admin kept off tenant hosts; unknown tenants and paths 404; assets; deleted again")
PY

echo "e2e.test.sh: ok"
