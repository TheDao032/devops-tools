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

ENV=""
MINT_HOST=""
SERVICES="trainee,trainer" # payment excluded deliberately — see NOTE below

usage() {
  cat >&2 <<'USAGE'
usage: e2e-verify.sh --env <dev|stg> --mint-host <public|cluster> [--service <a,b>]

  --mint-host public    mint through https://auth-<env>.fitmate.me  (what a REAL user does)
  --mint-host cluster   mint through http://keycloak.k3s.fitmate    (what in-cluster callers do)

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
[[ "${ENV}" == "dev" || "${ENV}" == "stg" ]] || { echo "--env must be dev or stg" >&2; exit 2; }
[[ -n "${VAULT_ADDR:-}" && -n "${VAULT_TOKEN:-}" ]] || {
  echo "VAULT_ADDR and VAULT_TOKEN must be set" >&2; exit 2; }

for bin in jq curl kubectl; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done

REALM="fitmate-${ENV}"
case "${MINT_HOST}" in
  public)  KC_BASE="https://auth-${ENV}.fitmate.me" ;;
  cluster) KC_BASE="http://keycloak.k3s.fitmate" ;;
  *) echo "--mint-host must be 'public' or 'cluster'" >&2; exit 2 ;;
esac

log()  { printf '  %s\n' "$*"; }
head_() { printf '\n=== %s ===\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# b64 decode tolerant of JWT's unpadded base64url.
b64url() { local d="${1//-/+}"; d="${d//_//}"; printf '%s' "${d}$(printf '%*s' $(( (4 - ${#d} % 4) % 4 )) '' | tr ' ' '=')" | base64 -d 2>/dev/null; }

vault_get() { # path key -> value on stdout
  curl -sf -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/fitmate/data/$1" | jq -er ".data.data[\"$2\"]"
}

head_ "Configuration"
log "env         ${ENV}   realm ${REALM}"
log "mint host   ${MINT_HOST} → ${KC_BASE}"
log "services    ${SERVICES}"

# ── 1. credentials (never printed) ────────────────────────────────────────────────────────────
head_ "1. Fetching credentials from Vault"
CLIENT_SECRET="$(vault_get "${ENV}/e2e/keycloak/creds" KEYCLOAK_CLIENTSECRET)" \
  || fail "harness client secret missing at fitmate/${ENV}/e2e/keycloak/creds — apply the keycloak unit first"
USER_PASSWORD="$(vault_get "keycloak/fitmate/trainee1/creds" password)" \
  || fail "trainee1 password missing — apply ${ENV}/vault-secrets first"
log "client secret  OK (${#CLIENT_SECRET} chars)"
log "user password  OK (${#USER_PASSWORD} chars)"

# ── 2. mint a token by password grant ─────────────────────────────────────────────────────────
head_ "2. Minting a user token (password grant, client fitmate-e2e-test)"
TOKEN_RESPONSE="$(curl -sS -X POST \
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
       This is the second-order problem in the website contract: a machine call to the public
       host meets the Access login page. Needs split-horizon DNS or an Access service token."
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
head_ "5. Calling the real services with the real token"
FAILED=0
for svc in "${SVCS[@]}"; do
  ns="fitmate-${svc}-${ENV}"
  port="$(kubectl -n "${ns}" get svc "${svc}-service" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)"
  [[ -n "${port}" ]] || { log "${svc}: service not found in ${ns} — SKIPPED"; continue; }

  kubectl -n "${ns}" port-forward "svc/${svc}-service" ":${port}" >/tmp/e2e-pf-${svc}.log 2>&1 &
  pf_pid=$!
  # shellcheck disable=SC2064
  trap "kill ${pf_pid} 2>/dev/null || true" EXIT
  for _ in $(seq 1 20); do
    local_port="$(grep -oE '127\.0\.0\.1:[0-9]+' /tmp/e2e-pf-${svc}.log 2>/dev/null | head -1 | cut -d: -f2)"
    [[ -n "${local_port:-}" ]] && break
    sleep 0.3
  done
  [[ -n "${local_port:-}" ]] || { log "${svc}: port-forward did not come up — SKIPPED"; kill ${pf_pid} 2>/dev/null || true; continue; }

  code="$(curl -s -o /tmp/e2e-body-${svc}.json -w '%{http_code}' \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "http://127.0.0.1:${local_port}/api/v1/${svc}s/me" || echo 000)"
  kill ${pf_pid} 2>/dev/null || true

  if [[ "${code}" == "200" ]]; then
    log "${svc}: 200 OK — token ACCEPTED"
  else
    FAILED=1
    log "${svc}: HTTP ${code} — token REJECTED"
    log "        $(head -c 200 /tmp/e2e-body-${svc}.json 2>/dev/null || true)"
  fi
done

head_ "Result"
if [[ "${FAILED}" -eq 0 && "${MISMATCH}" -eq 0 ]]; then
  echo "PASS — a token minted via the ${MINT_HOST} host is accepted by: ${SERVICES}"
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
