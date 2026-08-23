#!/usr/bin/env bash
# scripts/keycloak/e2e-verify.sh — prove that a token minted the way a real user mints it is
# ACCEPTED BY A REAL SERVICE. Not "the login page renders", not "the discovery document is
# correct" — an actual token, against an actual endpoint, asserted from the DECODED TOKEN.
#
# Why this exists (IN-17):
#   Every FitMate service validates `iss` with go-oidc's NewVerifier, which compares the claim
#   BYTE-FOR-BYTE against KEYCLOAK_ISSUER. Keycloak runs with hostname.strict=false, so `iss`
#   follows whichever host minted the token. Those two facts together mean a token can be
#   correctly signed, unexpired and correctly audienced — and still be rejected.
#
#   That defect (IN-16) survived because no automated check could obtain a user token: both
#   browser clients have direct_access_grants_enabled=false, so verification stopped at the
#   Keycloak admin API and the discovery document. Neither exercises `iss` against a service.
#
# THE TRAP THIS SCRIPT IS BUILT TO AVOID:
#   Minting through the IN-CLUSTER host produces iss=http://keycloak.k3s.fitmate/... which is
#   exactly what services expect today — so a naive harness would print PASS while real browser
#   logins fail. That is the same "green status attesting to the wrong proposition" that this
#   whole class of bug is made of. So --mint-host is REQUIRED and never defaulted, and the
#   decoded issuer is always printed and compared against the service's expectation.
#
# Usage:
#   scripts/keycloak/e2e-verify.sh --env dev --mint-host public
#   scripts/keycloak/e2e-verify.sh --env dev --mint-host cluster --service trainer
#
# Requires: VAULT_ADDR + VAULT_TOKEN (reads the harness secret and the seed password from Vault),
#           kubectl context on the target cluster, jq, curl.
# Never echoes a secret or a full token.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV=""
MINT_HOST=""
SERVICES="trainee,trainer" # payment excluded deliberately — see NOTE below

usage() {
  cat >&2 <<'USAGE'
usage: e2e-verify.sh --env <dev|stg> --mint-host <split|cluster|public> [--service <a,b>]

  --mint-host split     mint through the PUBLIC hostname but resolved straight to Traefik,
                        bypassing Cloudflare. THE ONE TO USE. Produces the same issuer a
                        browser gets, because Traefik picks its route (and its pinned
                        X-Forwarded-* headers) from the Host header, not from the source.

  --mint-host cluster   mint through http://keycloak.k3s.fitmate. Expected to FAIL since
                        IN-16: services accept only the public issuer now. Its failure is
                        the proof the issuer change took effect — run it deliberately.

  --mint-host public    mint through Cloudflare. CANNOT SUCCEED from a script: Cloudflare
                        Access challenges any non-browser caller and returns a login page
                        instead of a token. Kept so the limitation is documented, not
                        rediscovered. Use `split`.

There is no default. Choosing it for you is how IN-16 stayed hidden.

NOTE: payment-service is excluded from the default service list on purpose. Its only auth
middleware imports the retired SuperTokens SDK and is OFF by default, so it would return 200
for the wrong reason and manufacture a false PASS. (fitmate agent, B-P14 / SCRUM-165.)
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="${2:-}"; shift 2 ;;
    --mint-host) MINT_HOST="${2:-}"; shift 2 ;;
    --service) SERVICES="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "${ENV}" && -n "${MINT_HOST}" ]] || usage
# Validate the mode BEFORE anything else. Otherwise a typo'd --mint-host surfaces as
# "VAULT_ADDR and VAULT_TOKEN must be set", which sends you to debug credentials over a flag.
case "${MINT_HOST}" in
  split|cluster|public) ;;
  *) echo "--mint-host must be 'split', 'cluster' or 'public' (got '${MINT_HOST}')" >&2; usage ;;
esac
[[ "${ENV}" == "dev" || "${ENV}" == "stg" ]] || { echo "--env must be dev or stg" >&2; exit 2; }
[[ -n "${VAULT_ADDR:-}" && -n "${VAULT_TOKEN:-}" ]] || {
  echo "VAULT_ADDR and VAULT_TOKEN must be set" >&2; exit 2; }

for bin in jq curl kubectl; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done

log()  { printf '  %s\n' "$*"; }
head_() { printf '\n=== %s ===\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

REALM="fitmate-${ENV}"
PUBLIC_HOST="auth-${ENV}.fitmate.me"
CANONICAL_ISSUER="https://${PUBLIC_HOST}/realms/${REALM}"

# RESOLVE is passed to curl only in split mode. Declared empty otherwise and always expanded
# with the ${arr[@]+...} guard — macOS ships bash 3.2, where "${arr[@]}" on an empty array is
# an error under `set -u`.
RESOLVE=()

case "${MINT_HOST}" in
  public)
    KC_BASE="https://${PUBLIC_HOST}"
    ;;
  cluster)
    KC_BASE="http://keycloak.k3s.fitmate"
    ;;
  split)
    # Same URL a browser uses, but curl connects to Traefik directly instead of asking DNS
    # (which would answer with Cloudflare). The Host header still says the public name, so
    # Traefik matches the keycloak-auth-<env> HTTPRoute and applies its pinned X-Forwarded-*
    # headers — which is what makes Keycloak stamp the canonical https issuer even though
    # this hop is plain HTTP on :80. Port 80 here is the transport; the `https` in the issuer
    # comes from the pinned header (IN-20), not from the connection.
    TRAEFIK_LB="$(kubectl -n traefik get svc traefik \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    [[ -n "${TRAEFIK_LB:-}" ]] || fail "could not read the Traefik LoadBalancer IP — is kubectl pointed at the right cluster?"
    KC_BASE="http://${PUBLIC_HOST}"
    RESOLVE=(--resolve "${PUBLIC_HOST}:80:${TRAEFIK_LB}")
    ;;
  *) echo "--mint-host must be 'split', 'cluster' or 'public'" >&2; exit 2 ;;
esac


# b64 decode tolerant of JWT's unpadded base64url.
b64url() { local d="${1//-/+}"; d="${d//_//}"; printf '%s' "${d}$(printf '%*s' $(( (4 - ${#d} % 4) % 4 )) '' | tr ' ' '=')" | base64 -d 2>/dev/null; }

vault_get() { # path key -> value on stdout; prints the attempted path on failure
  local out
  if ! out="$(curl -sf -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/fitmate/data/$1" 2>/dev/null)"; then
    printf '  vault read FAILED: fitmate/data/%s (path absent, or token lacks access)\n' "$1" >&2
    return 1
  fi
  if ! jq -er ".data.data[\"$2\"]" <<<"${out}" 2>/dev/null; then
    printf '  vault path fitmate/data/%s exists but has no key %s. Keys present: %s\n' \
      "$1" "$2" "$(jq -r '.data.data | keys | join(", ")' <<<"${out}" 2>/dev/null)" >&2
    return 1
  fi
}

head_ "Configuration"
log "env         ${ENV}   realm ${REALM}"
log "mint host   ${MINT_HOST} → ${KC_BASE}"
[[ ${#RESOLVE[@]} -gt 0 ]] && log "resolve     ${PUBLIC_HOST} → ${TRAEFIK_LB} (Cloudflare bypassed)"
log "services    ${SERVICES}"
# Provenance. A `terragrunt apply` run from a stale branch succeeds and silently does nothing,
# which then surfaces here as "missing secret — apply first" and sends you round the loop again.
# Printing what the config came from makes that visible at a glance.
if ENVS_DIR="$(cd "${SCRIPT_DIR}/../../../devops-terragrunt-environments" 2>/dev/null && pwd)"; then
  log "env config  $(git -C "${ENVS_DIR}" branch --show-current 2>/dev/null)@$(git -C "${ENVS_DIR}" rev-parse --short HEAD 2>/dev/null)$(git -C "${ENVS_DIR}" diff --quiet 2>/dev/null || echo ' (DIRTY)')"
fi

# ── 1. credentials (never printed) ────────────────────────────────────────────────────────────
head_ "1. Fetching credentials from Vault"
CLIENT_SECRET="$(vault_get "${ENV}/e2e/keycloak/creds" KEYCLOAK_CLIENTSECRET)" \
  || fail "harness client secret not readable at fitmate/${ENV}/e2e/keycloak/creds — apply <env>/keycloak/fitmate, and check the repo is on the MERGED branch (see provenance above)"
# NOTE the ${ENV}/ prefix. vault-secrets writes APP-level secrets under fitmate/data/<env>/*
# (path_prefix "<env>/"), so the key as written in env.hcl — "keycloak/fitmate/trainee1/creds" —
# is NOT the Vault path. Omitting the prefix reads a path that never existed and reports it as
# "not applied", which sends you to re-run an apply that was already correct.
USER_PASSWORD="$(vault_get "${ENV}/keycloak/fitmate/trainee1/creds" password)" \
  || fail "trainee1 password not readable at fitmate/${ENV}/keycloak/fitmate/trainee1/creds"
log "client secret  OK (${#CLIENT_SECRET} chars)"
log "user password  OK (${#USER_PASSWORD} chars)"

# ── 1b. split mode ONLY: prove this path stamps the CANONICAL issuer before trusting it ───────
#
# Without this check, split mode is just "a way to reach Keycloak" and a future header regression
# would make it silently verify the wrong thing. That already happened once: pinning
# X-Forwarded-Proto without X-Forwarded-Port produced https://auth-dev.fitmate.me:80/... which is
# a different issuer to every service on the cluster. A green PASS from this harness must never be
# reachable while that is true.
if [[ "${MINT_HOST}" == "split" ]]; then
  head_ "1b. Verifying the split path stamps the canonical issuer"
  DISCO_ISS="$(curl -sf ${RESOLVE[@]+"${RESOLVE[@]}"} --max-time 10 \
    "${KC_BASE}/realms/${REALM}/.well-known/openid-configuration" 2>/dev/null \
    | jq -r '.issuer' 2>/dev/null || true)"
  [[ -n "${DISCO_ISS}" ]] || fail "could not fetch the discovery document via ${TRAEFIK_LB} — is the HTTPRoute applied?"
  log "discovery issuer  ${DISCO_ISS}"
  log "canonical issuer  ${CANONICAL_ISSUER}"
  if [[ "${DISCO_ISS}" != "${CANONICAL_ISSUER}" ]]; then
    fail "split path issuer does NOT match the canonical value.
       got:      ${DISCO_ISS}
       expected: ${CANONICAL_ISSUER}
       The pinned X-Forwarded-Host/Proto/Port on the keycloak-auth-${ENV} HTTPRoute are wrong or
       unapplied (IN-20). Any result from this mode would be meaningless until that is fixed."
  fi
  log "match — this path is equivalent to the browser path for issuer purposes"
fi

# ── 2. mint a token by password grant ─────────────────────────────────────────────────────────
head_ "2. Minting a user token (password grant, client fitmate-e2e-test)"
TOKEN_RESPONSE="$(curl -sS ${RESOLVE[@]+"${RESOLVE[@]}"} -X POST \
  "${KC_BASE}/realms/${REALM}/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password' \
  -d 'client_id=fitmate-e2e-test' \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  -d 'username=trainee1' \
  --data-urlencode "password=${USER_PASSWORD}" \
  -d 'scope=openid' 2>&1)" || fail "token request failed to connect"

ACCESS_TOKEN="$(jq -er '.access_token' <<<"${TOKEN_RESPONSE}" 2>/dev/null)" || {
  # Surface Keycloak's own error, but never the request body.
  ERR="$(jq -r '.error_description // .error // "unparseable response"' <<<"${TOKEN_RESPONSE}" 2>/dev/null || echo "unparseable response")"
  if [[ "${MINT_HOST}" == "public" ]] && grep -qi 'cloudflare\|<html' <<<"${TOKEN_RESPONSE}"; then
    fail "got an HTML page, not a token — Cloudflare Access is gating the token endpoint.

       THIS IS EXPECTED AND IS NOT A FAULT. Access challenges any caller that is not a
       logged-in browser, and a script is exactly that. No infrastructure change will make
       --mint-host public succeed, and it should not: weakening Access to satisfy a test
       would remove the only control currently keeping the IN-20 header-forgery hole off
       the public internet.

       Use --mint-host split instead. Same hostname, same issuer, resolved straight to
       Traefik so Cloudflare is not in the path.

       (The same wall will meet the website's server-side token refresh, which calls this
       endpoint from the Next.js pod. That needs real split-horizon DNS in-cluster — a
       separate change, tracked on IN-16.)"
  fi
  fail "no access_token: ${ERR}"
}
log "token acquired (${#ACCESS_TOKEN} chars, not printed)"

# ── 3. decode and assert FROM THE TOKEN, not from config ──────────────────────────────────────
head_ "3. Decoding the token — asserting from the token itself"
PAYLOAD="$(b64url "$(cut -d. -f2 <<<"${ACCESS_TOKEN}")")" || fail "could not decode token payload"
TOK_ISS="$(jq -r '.iss' <<<"${PAYLOAD}")"
TOK_AUD="$(jq -r '(.aud | if type=="array" then join(",") else . end)' <<<"${PAYLOAD}")"
TOK_ROLES="$(jq -r '(.realm_access.roles // []) | sort | join(",")' <<<"${PAYLOAD}")"
TOK_SUB="$(jq -r '.preferred_username // .sub' <<<"${PAYLOAD}")"
log "iss    ${TOK_ISS}"
log "aud    ${TOK_AUD}"
log "roles  ${TOK_ROLES}"
log "user   ${TOK_SUB}"

grep -q 'fitmate-backend' <<<"${TOK_AUD}" \
  || fail "aud does not contain fitmate-backend (got '${TOK_AUD}') — every service will reject this"

# ── 4. compare against what each service actually expects ─────────────────────────────────────
head_ "4. Comparing the token's issuer against each service's configured issuer"
MISMATCH=0
IFS=',' read -ra SVCS <<<"${SERVICES}"
for svc in "${SVCS[@]}"; do
  ns="fitmate-${svc}-${ENV}"
  expected="$(kubectl -n "${ns}" get secret "${svc}-service-secrets" \
    -o jsonpath='{.data.KEYCLOAK_ISSUER}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  if [[ -z "${expected}" ]]; then
    log "${svc}: KEYCLOAK_ISSUER not found in ${ns}/${svc}-service-secrets — SKIPPED"
    continue
  fi
  if [[ "${expected}" == "${TOK_ISS}" ]]; then
    log "${svc}: MATCH   ${expected}"
  else
    MISMATCH=1
    log "${svc}: MISMATCH"
    log "        token expects service to accept  ${TOK_ISS}"
    log "        service is configured to accept  ${expected}"
  fi
done

# ── 5. the assertion that actually matters ────────────────────────────────────────────────────
# ── 5. call the real services ─────────────────────────────────────────────────────────────────
#
# PROBE TABLE — explicit per service. There is NO general "/api/v1/<svc>s/me" convention; assuming
# one produced a false failure on trainer-service, whose routes are all :id-based, so "me" parsed
# as an ID and returned 400 before auth was ever consulted.
#
# A probe is only usable if the route is genuinely behind KeycloakVerifySession AND is read-only.
# Verified against services/back-end/* on 2026-08-23:
#
#   trainee  GET /api/v1/trainees/me   KeycloakVerifySession   read-only   -> USABLE
#   trainer  no read-only guarded route. Its GET routes (`/trainers`, `/trainers/:id`) are
#            UNAUTHENTICATED; its guarded routes are all mutations (POST /trainers,
#            PUT /trainers/:id, PATCH /:id/approve). A verification harness must not create or
#            modify data, so trainer is skipped rather than probed with a write.
#   payment  excluded entirely — its only auth middleware imports the retired SuperTokens SDK and
#            is OFF by default, so it answers 200 without validating anything (B-P14/SCRUM-165).
#
# ⚠️ `set -o pipefail` is active: a pipeline whose first stage fails (grep matching nothing)
# returns non-zero and, inside $(...), trips `set -e` and kills the script with NO output. This
# step previously did exactly that — printed its header and vanished. Hence the `|| true`s.
head_ "5. Calling the real services with the real token"

probe_for() { # svc -> "METHOD PATH" or "" when there is no usable probe
  case "$1" in
    trainee) echo "GET /api/v1/trainees/me" ;;
    *)       echo "" ;;
  esac
}

PF_PIDS=()
cleanup() { for p in ${PF_PIDS[@]+"${PF_PIDS[@]}"}; do kill "${p}" 2>/dev/null || true; done; }
trap cleanup EXIT

FAILED=0
ATTEMPTED=0
for svc in "${SVCS[@]}"; do
  ns="fitmate-${svc}-${ENV}"
  probe="$(probe_for "${svc}")"

  if [[ -z "${probe}" ]]; then
    log "${svc}: SKIPPED — no read-only Keycloak-guarded endpoint exists to probe"
    log "        (guarded routes are mutations; a verification run must not write data)"
    continue
  fi
  method="${probe%% *}"; path="${probe#* }"

  if ! kubectl -n "${ns}" get svc "${svc}-service" >/dev/null 2>&1; then
    log "${svc}: SKIPPED — no svc/${svc}-service in ${ns}"
    continue
  fi
  port="$(kubectl -n "${ns}" get svc "${svc}-service" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)"
  [[ -n "${port}" ]] || { log "${svc}: SKIPPED — could not read a port from svc/${svc}-service"; continue; }

  pf_log="$(mktemp -t "e2e-pf.XXXXXX")"
  kubectl -n "${ns}" port-forward "svc/${svc}-service" ":${port}" >"${pf_log}" 2>&1 &
  pf_pid=$!
  PF_PIDS+=("${pf_pid}")

  local_port=""
  for _ in $(seq 1 30); do
    kill -0 "${pf_pid}" 2>/dev/null || break
    local_port="$(grep -oE '127\.0\.0\.1:[0-9]+' "${pf_log}" 2>/dev/null | head -1 | cut -d: -f2 || true)"
    if [[ -n "${local_port}" ]] && curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${local_port}/" 2>/dev/null; then break; fi
    sleep 0.3
  done
  if [[ -z "${local_port}" ]]; then
    log "${svc}: SKIPPED — port-forward never came up: $(tail -2 "${pf_log}" 2>/dev/null | tr '\n' ' ' || true)"
    { kill "${pf_pid}"; wait "${pf_pid}"; } 2>/dev/null || true
    rm -f "${pf_log}"; continue
  fi

  url="http://127.0.0.1:${local_port}${path}"
  body="$(mktemp -t "e2e-body.XXXXXX")"

  # NEGATIVE CONTROL FIRST. A garbage token must be REJECTED. Without this, an unguarded route
  # returns 200 to anything and the harness reports PASS having verified nothing — exactly the
  # failure mode that makes payment-service unusable as a probe.
  # Built from parts rather than written inline: a literal string after "Bearer " trips the
  # gitleaks curl-auth-header rule. It is a deliberate non-credential, but the hook cannot know
  # that, and silencing a secret scanner to keep a placeholder is a bad trade.
  BAD_TOKEN="invalid-$(printf 'placeholder')-value"
  neg="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X "${method}" \
    -H "Authorization: Bearer ${BAD_TOKEN}" "${url}" 2>/dev/null || echo 000)"
  if [[ "${neg}" != "401" && "${neg}" != "403" ]]; then
    FAILED=1
    log "${svc}: CONTROL FAILED — an invalid token got HTTP ${neg} from ${method} ${path}"
    log "        The endpoint is not enforcing authentication, so a PASS here would prove nothing."
    { kill "${pf_pid}"; wait "${pf_pid}"; } 2>/dev/null || true
    rm -f "${pf_log}" "${body}"; continue
  fi
  log "${svc}: control OK — invalid token rejected with ${neg}"

  ATTEMPTED=$((ATTEMPTED + 1))
  code="$(curl -s -o "${body}" -w '%{http_code}' --max-time 15 -X "${method}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" "${url}" 2>/dev/null || echo 000)"
  { kill "${pf_pid}"; wait "${pf_pid}"; } 2>/dev/null || true

  if [[ "${code}" == "200" ]]; then
    log "${svc}: 200 OK — real token ACCEPTED by ${method} ${path}"
  else
    FAILED=1
    log "${svc}: HTTP ${code} — real token REJECTED by ${method} ${path}"
    log "        $(head -c 300 "${body}" 2>/dev/null | tr '\n' ' ' || true)"
  fi
  rm -f "${pf_log}" "${body}"
done

# "Nothing was checked" and "everything passed" are different claims. Only one is evidence.
if [[ "${ATTEMPTED}" -eq 0 ]]; then
  head_ "Result"
  echo "INCONCLUSIVE — no service was actually probed. Nothing was verified." >&2
  exit 1
fi

head_ "Result"
if [[ "${FAILED}" -eq 0 && "${MISMATCH}" -eq 0 ]]; then
  echo "PASS — a token minted via the ${MINT_HOST} path was accepted by ${ATTEMPTED} probed service(s)."
  echo "       Each probe was negative-controlled: an invalid token was rejected first."
  if [[ "${MINT_HOST}" == "split" ]]; then
    # Say precisely what was and was not exercised. A PASS that overstates its scope is the
    # same failure this harness exists to prevent, just wearing a green colour.
    echo "       Issuer verified identical to the browser path (checked in step 1b)."
    echo "       NOT exercised: Cloudflare edge, the tunnel, and the Access policy itself."
  fi
  exit 0
fi
if [[ "${MISMATCH}" -eq 1 ]]; then
  cat >&2 <<EOF
FAIL — issuer mismatch (this is IN-16).

The token's iss is '${TOK_ISS}'. At least one service is configured to accept a different
string, and go-oidc compares them byte-for-byte. The token is otherwise valid.

If you minted with --mint-host cluster and it PASSED, that proves nothing about real users:
browsers reach Keycloak through the public host and get a different iss. Re-run with
--mint-host public before believing any green result.
EOF
  exit 1
fi
echo "FAIL — a service rejected the token; see above" >&2
exit 1
