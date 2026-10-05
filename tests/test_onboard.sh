#!/usr/bin/env bash
# Runs onboard.sh against stubbed gh/curl in a throwaway git repo. No network, no real GitHub.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

setup() {
  W="$(mktemp -d)"
  mkdir -p "$W/bin" "$W/remote.git" "$W/clone"
  git init -q --bare -b main "$W/remote.git"
  git -C "$W/clone" init -q -b main
  git -C "$W/clone" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$W/clone" remote add origin "$W/remote.git"
  git -C "$W/clone" push -q origin main
  : >"$W/gh.log"
  cat >"$W/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >>"$W/gh.log"
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") echo "alice/new" ;;
  "api repos/alice/new")
    case "$*" in *permissions.admin*) echo "${FAKE_ADMIN:-true}" ;; *default_branch*) echo main ;; esac ;;
  "secret list") [ -n "${FAKE_HAS_SECRET:-}" ] && echo ATOBAR_TENANT_TOKEN; true ;;
  "secret set") cat >"$W/secret.value" ;;
  "pr list"|"issue list") true ;;
  "pr create") echo "https://github.com/alice/new/pull/1" ;;
  "label create") true ;;
  "issue create") cat >"$W/issue.body"; echo "https://github.com/alice/new/issues/2" ;;
  "api repos/alice/new/contents/.github/workflows/flow-trigger.yml?ref=main") exit 1 ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
GH
  cat >"$W/bin/curl" <<'CURL'
#!/usr/bin/env bash
echo "curl $*" >>"$W/curl.log"
case "$*" in
  *healthz*) echo '{"status":"ok"}' ;;
  */v1/tenant*) h="$(cat)"; [ "$h" = "Authorization: Bearer atb_good" ] && echo '{"repo":"alice/new","status":"onboarding"}' || exit 22 ;;
  *flow-trigger.yml*) while [ "$#" -gt 1 ] && [ "$1" != -o ]; do shift; done; printf 'name: flow Trigger\n' >"$2" ;;
  *) exit 7 ;;
esac
CURL
  printf '#!/bin/sh\nexit 0\n' >"$W/bin/xdg-open"; cp "$W/bin/xdg-open" "$W/bin/open"
  chmod +x "$W/bin/gh" "$W/bin/curl" "$W/bin/xdg-open" "$W/bin/open"
  export W PATH="$W/bin:$PATH" ATOBAR_YES=1 ATOBAR_TTY=/nonexistent
}

run() { (cd "$W/clone" && bash "$ROOT/onboard.sh") >"$W/out" 2>&1; }

# Happy path: token verified, secret stored, trigger PR pushed, spec issue opened.
setup
echo atb_good >"$W/token"; export ATOBAR_TOKEN_FILE="$W/token"
run || { cat "$W/out"; fail "happy path exited non-zero"; }
[ "$(cat "$W/secret.value")" = atb_good ] || fail "secret not stored"
grep -q atb_good "$W/out" "$W/gh.log" && fail "token leaked to output or argv"
grep -q "Authorization" "$W/curl.log" && fail "token passed on curl argv"
git -C "$W/remote.git" show atobar/onboard:.github/workflows/flow-trigger.yml | grep -q "flow Trigger" || fail "trigger not pushed"
[ "$(git -C "$W/clone" rev-parse --abbrev-ref HEAD)" = main ] || fail "did not return to original branch"
grep -q "evaluation spec" "$W/issue.body" || fail "spec issue body missing"
grep -q "Build from zero" "$W/issue.body" && fail "non-empty repo got build-from-zero section"
grep -q "label create flow:onboard" "$W/gh.log" || fail "label not created"
echo "ok happy path"

# Wrong token is rejected and never stored.
setup
echo atb_bad >"$W/token"; export ATOBAR_TOKEN_FILE="$W/token"
run && fail "bad token accepted"
[ -e "$W/secret.value" ] && fail "bad token stored"
grep -q "did not accept" "$W/out" || fail "missing rejection message"
echo "ok rejects foreign token"

# Not a token at all.
setup
echo ghp_x >"$W/token"; export ATOBAR_TOKEN_FILE="$W/token"
run && fail "non-atb token accepted"
echo "ok rejects non-tenant token"

# Non-admins stop before any mutation.
setup
export FAKE_ADMIN=false
run && fail "non-admin allowed"
grep -q "must be an admin" "$W/out" || fail "missing admin message"
grep -qE "secret set|pr create|issue create" "$W/gh.log" && fail "mutated as non-admin"
unset FAKE_ADMIN
echo "ok requires admin"

# Existing secret is kept unless ATOBAR_ROTATE=1.
setup
export FAKE_HAS_SECRET=1; unset ATOBAR_TOKEN_FILE
run || { cat "$W/out"; fail "existing-secret path failed"; }
[ -e "$W/secret.value" ] && fail "secret overwritten without ATOBAR_ROTATE"
unset FAKE_HAS_SECRET
echo "ok keeps existing secret"

# Empty repository: the trigger becomes the first commit on main and the spec asks what to build.
setup
rm -rf "$W/remote.git" "$W/clone"; git init -q --bare -b main "$W/remote.git"
git clone -q "$W/remote.git" "$W/clone" 2>/dev/null
echo atb_good >"$W/token"; export ATOBAR_TOKEN_FILE="$W/token"
run || { cat "$W/out"; fail "empty repo exited non-zero"; }
git -C "$W/remote.git" show main:.github/workflows/flow-trigger.yml | grep -q "flow Trigger" || fail "trigger not on main"
git -C "$W/remote.git" show main:README.md >/dev/null || fail "README not committed"
[ "$(git -C "$W/remote.git" rev-list --count main)" = 1 ] || fail "expected exactly one commit"
grep -q "pr create" "$W/gh.log" && fail "opened a PR against an empty repo"
grep -q "Build from zero" "$W/issue.body" || fail "spec issue lacks build-from-zero section"
echo "ok empty repository"

# Empty on GitHub but the clone has unpushed commits: stop before touching anything.
setup
rm -rf "$W/remote.git"; git init -q --bare -b main "$W/remote.git"
run && fail "ran with unpushed local commits"
grep -q "push them first" "$W/out" || fail "missing push-first message"
grep -qE "secret set|issue create" "$W/gh.log" && fail "mutated with unpushed commits"
echo "ok unpushed clone"

# Outside a git repository.
setup
(cd "$W" && bash "$ROOT/onboard.sh") >"$W/out" 2>&1 && fail "ran outside a clone"
grep -q "inside a clone" "$W/out" || fail "missing clone message"
echo "ok requires a clone"

echo "all tests passed"
