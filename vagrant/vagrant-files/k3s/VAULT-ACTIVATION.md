# Activating Vault (HA Raft + TLS, Shamir) on the k3s-etcd lab

Vault is deployed by the Terragrunt `k3s-resources` unit
(`devops-terragrunt-environments/on-prem/fitmate/local/k3s-resources`) as a **3-replica
HA cluster** using **integrated Raft storage**, **TLS** (self-signed via cert-manager),
and **Shamir** unsealing. After `terragrunt run -- apply`, the pods are **Running but
sealed + uninitialized** — this doc is the one-time activation runbook.

> `kubectl` here assumes `KUBECONFIG` points at the lab kubeconfig (direnv exports it in
> `.../fitmate/local/k3s-resources`, or run `./fetch-kubeconfig.sh` to write `./kubeconfig`).

## Quick path — the scripts (recommended for this restart-heavy lab)

Because Shamir re-seals on every pod restart (and you stop the VMs often), use the helper
scripts instead of typing keys by hand. They reuse your **chezmoi `age` key**
(`~/.config/chezmoi/key.txt`) so the unseal keys live **age-encrypted at rest**, never in
a plaintext file or a k8s Secret.

```bash
./fetch-kubeconfig.sh     # once per cluster — writes ./kubeconfig (git-ignored)
./vault-activate.sh       # do-the-right-thing: init if fresh, unseal if already inited
```

`vault-activate.sh` is the single entrypoint — it inspects the cluster and picks the
correct action, so you don't have to remember whether this cluster needs init or just
unseal:

| Cluster state | What activate does |
|---|---|
| Vault not deployed yet (fresh `destroy` + `up`) | graceful no-op — deploy Vault via Terragrunt, then re-run |
| Vault deployed, `initialized=false` (fresh cluster) | rotates any stale `vault-init.age` aside → `operator init` → unseal |
| Vault deployed, `initialized=true` (`halt` → `up`) | unseal only |

It is also **wired into `vagrant up`** as an `after :up` trigger, so a plain `halt`→`up`
re-unseals hands-off. On a `destroy`→`up`, the trigger no-ops (Vault isn't deployed during
`vagrant up`); after you apply the Terragrunt `k3s-resources` unit, run `./vault-activate.sh`
once to init the fresh Vault.

**Why re-init after a destroy is safe:** a deployed Vault reporting `initialized=false`
*proves* any `vault-init.age` on disk is dead — those keys can't belong to a Vault that
says it was never initialized. `vault-activate.sh` rotates the stale keystore to
`vault-init.age.stale-<timestamp>` (git-ignored, safe to delete) before re-initing.

The two lower-level scripts still exist for manual/debug use:

- `vault-init.sh` — idempotent one-time init; refuses to re-init an already-initialized
  Vault or overwrite an existing `vault-init.age` (so it's safe, but on a destroy+up you'd
  hit "keystore exists but Vault uninitialized" — that's exactly the stale-keystore case
  `vault-activate.sh` handles for you).
- `vault-unseal.sh` — unseals `vault-0/1/2`, skipping pods already unsealed.
- `vault-init.age` + `kubeconfig` are git-ignored. Inspect the keys with
  `age -d -i ~/.config/chezmoi/key.txt vault-init.age | jq .`.

The manual steps below are the same operations the scripts run — keep them as reference /
for debugging.

---

## 0. Confirm the pre-activation state
```bash
kubectl -n vault get pods -o wide           # vault-0/1/2 Running (1/1 Ready via custom probe)
kubectl -n vault exec -it vault-0 -- vault status
# Seal Type: shamir | Initialized: false | Sealed: true | Storage Type: raft
```
Pods show `1/1 Ready` even while sealed — the readiness probe treats
`sealedcode=204&uninitcode=204` as ready. Vault is **not usable** until initialized + unsealed.

## 1. Initialize — ONCE, EVER (on vault-0)
```bash
kubectl -n vault exec -it vault-0 -- vault operator init \
  -key-shares=5 -key-threshold=3 -format=json | tee vault-init.json
```
Output contains 5 `unseal_keys_b64` + a `root_token`.

> 🔑 **Save `vault-init.json` to SOPS / a password manager immediately, then shred the
> plaintext.** Shamir mode has **no recovery keys** — these unseal keys are the only way
> in. Losing them = losing Vault permanently.

## 2. Unseal vault-0 (3 of 5 keys → becomes Raft leader)
```bash
kubectl -n vault exec -it vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl -n vault exec -it vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl -n vault exec -it vault-0 -- vault operator unseal <UNSEAL_KEY_3>
```

## 3. Unseal vault-1 and vault-2
They auto-join the Raft cluster via the `retry_join` stanzas; they only need unsealing
with the **same** keys:
```bash
for p in vault-1 vault-2; do
  for k in <UNSEAL_KEY_1> <UNSEAL_KEY_2> <UNSEAL_KEY_3>; do
    kubectl -n vault exec -it "$p" -- vault operator unseal "$k"
  done
done
```

## 4. Verify the HA Raft cluster
```bash
kubectl -n vault exec -it vault-0 -- vault status          # Sealed:false, HA Mode:active
ROOT=$(jq -r .root_token vault-init.json)
kubectl -n vault exec -it vault-0 -- sh -c "VAULT_TOKEN=$ROOT vault operator raft list-peers"
# vault-0 leader; vault-1, vault-2 follower; voter=true for all
```

## 5. Log in / reach the UI
```bash
kubectl -n vault exec -it vault-0 -- vault login "$ROOT"

# UI via ingress: add to /etc/hosts →  192.168.105.10  vault.k3s.local
#   then browse https://vault.k3s.local  (self-signed CA — accept it)
# or port-forward:
kubectl -n vault port-forward svc/vault 8200:8200
#   VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault status
```

## Operational notes
- **Shamir = manual unseal on every pod restart.** If any `vault-N` restarts it comes back
  sealed → re-run step 2/3 for that pod. To make this hands-off later, add a
  `seal "transit"` (or a cloud KMS seal) stanza to the chart values and re-deploy.
- **Root token** is for bootstrap only. Create scoped tokens / auth methods, then revoke or
  stash the root token.
- **TLS:** the CLI inside the pod trusts the cert-manager CA via `VAULT_CACERT`
  (`/vault/userconfig/vault-tls-server/ca.crt`); `127.0.0.1` and the k8s service DNS names
  are in the cert SANs, so no `-tls-skip-verify` is needed in-pod.

## Next steps (post-activation)
1. **Enable the Kubernetes auth method** so External Secrets Operator can authenticate.
2. **Enable a KV v2 secrets engine** + write app secrets.
3. Apply the `vault-roles` / `vault-secrets` Terragrunt units (they need `VAULT_ADDR` +
   `VAULT_TOKEN` exported — see `vault-config.hcl`).
4. Wire `ExternalSecret` / `SecretStore` resources for the workloads.

## Related
- Deployment modes / why HA-Raft+TLS: devops-architect vault brain →
  `30-references/vault-on-k8s-deployment-modes`
- Auto-unseal options (Transit / KMS): `30-references/vault-auto-unseal-methods`
- Full activation runbook mirror: `30-references/vault-k3s-activation`
