# GCP Project Recreation — Fresh `repsaga-prod` Runbook

Complete top-to-bottom runbook for replacing the old GymBuddy-era GCP project with a fresh `repsaga-prod` project. Follow linearly; do not skip verifications. Rollback note at the end.

**Constants used throughout** (already known from the repo):

- Supabase project ref: `dgcueqvqfyuedclkxixz`
- Edge Functions base URL: `https://dgcueqvqfyuedclkxixz.supabase.co/functions/v1`
- RTDN webhook URL: `https://dgcueqvqfyuedclkxixz.supabase.co/functions/v1/rtdn-webhook`
- Android package: `com.repsaga.app`
- Play subscription product ID: `repsaga_premium`

**Legend:**

- 🧑 = you (console clicks or local terminal)
- 🤖 = Claude runs it in-session

---

## Phase 0 — Preflight

Pre-launch state: no real purchases, no RTDN traffic, zero users affected by breaking the old project. Preflight is minimal — just confirm tooling works and note the old project ID so you can delete it at the end.

### 0.1 🧑 Confirm gcloud is installed + authenticated + note old project ID

```bash
gcloud auth list
gcloud config get-value project
```

**If `gcloud` isn't installed:** install from <https://cloud.google.com/sdk/docs/install>, then `gcloud init` → sign in with the Google account tied to your GCP account.

Old project ID (record for Phase 13 cleanup): `gymbuddy-app-proj`

- [x] gcloud confirmed working
- [x] Old project ID recorded above

---

## Phase 1 — Create the new GCP project

### 1.1 🧑 Create project

1. Open <https://console.cloud.google.com/>
2. Top bar → project selector dropdown → **New Project**
3. Fields:
   - **Project name:** `RepSaga`
   - **Project ID:** click **Edit** and set to `repsaga-prod`
     - Must be globally unique, 6–30 chars, lowercase letters/digits/hyphens, starts with a letter, ends with letter/digit
     - If taken, try `repsaga-app`, `repsaga-gym`, `repsaga-production`
     - **WRITE DOWN THE FINAL PROJECT ID** — you'll paste it into ~8 places below. Wherever you see `repsaga-prod` in this runbook, substitute whatever you actually used.
   - **Organization:** same as old project (or "No organization" if that's what you had)
   - **Location:** same folder as old project, or leave default
4. Click **Create**. Wait ~10 seconds for the green "Project created" toast.
5. Select the new project in the top-bar project picker.

Final project ID: `repsaga-prod`
Project number: `359507774133` (used in Phase 5.2)

- [x] Project created
- [x] Final project ID written down above

### 1.2 🧑 Verify

```bash
gcloud config set project repsaga-prod
gcloud projects describe repsaga-prod
```

Expected: `lifecycleState: ACTIVE`.

- [x] Verified ACTIVE (2026-04-22)

---

## Phase 2 — Link billing account

GCP APIs will not serve requests without billing, even on the free tier. Pub/Sub + Play Developer API both require it.

### 2.1 🧑 Link

1. Console → **Billing** (hamburger menu) → **Link a billing account**
2. Pick the same billing account the old project used (or the one attached to your Google Cloud profile)
3. Confirm

- [x] Billing linked (account `018BB8-45BF5A-BECE0F`)

### 2.2 🧑 Verify

```bash
gcloud beta billing projects describe repsaga-prod
```

Expected: `billingEnabled: true`.

- [x] Verified (2026-04-22)

---

## Phase 3 — Enable the APIs we use

### 3.1 🧑 Enable via CLI (faster than clicking)

```bash
gcloud services enable \
  androidpublisher.googleapis.com \
  pubsub.googleapis.com \
  iamcredentials.googleapis.com \
  --project=repsaga-prod
```

`iamcredentials` is needed so Pub/Sub can mint the OIDC token it attaches to push requests.

- [x] APIs enabled (androidpublisher, pubsub, iamcredentials)

### 3.2 🧑 Verify

```bash
gcloud services list --enabled --project=repsaga-prod \
  --format="value(config.name)" \
  | grep -E "(androidpublisher|pubsub|iamcredentials)"
```

Expected: 3 lines.

- [x] Verified (2026-04-22)

---

## Phase 4 — Create the Play API service account

### 4.1 🧑 Create

Console → **IAM & Admin** → **Service Accounts** → **Create service account**

- **Service account name:** `repsaga-play-api`
- **Service account ID:** leave auto-generated (will be `repsaga-play-api`)
- **Description:** `Server-to-server calls to Play Developer API (validate, acknowledge, reconcile).`
- Click **Create and Continue**
- **Grant this service account access to project:** leave blank. Do NOT grant project roles. Click **Continue**.
- **Grant users access:** leave blank. Click **Done**.

- [x] SA created

### 4.2 🧑 Create and download JSON key

1. Click the new SA row (email like `repsaga-play-api@repsaga-prod.iam.gserviceaccount.com`)
2. **Keys** tab → **Add Key** → **Create new key**
3. **Key type:** JSON → **Create**
4. Browser downloads `repsaga-prod-xxxxxxxxxxxx.json`
5. **Move it to a safe, stable location** — e.g. `~/secrets/repsaga-play-api.json` or into 1Password/Bitwarden. Do NOT leave it in `~/Downloads`.

Path to stored key (Phase 9 input): `C:\Users\caiol\secrets\repsaga-prod-a558218af29e.json`

- [x] JSON key downloaded and moved to safe location
- [x] Path recorded above

### 4.3 🧑 Verify

```bash
gcloud iam service-accounts list --project=repsaga-prod
```

Expected: one entry, `repsaga-play-api@repsaga-prod.iam.gserviceaccount.com`, not disabled.

- [x] Verified (2026-04-22)

---

## Phase 5 — Create a separate push-auth service account

Deliberately use a **different** SA for Pub/Sub → Edge Function OIDC push auth, not the Play API SA. This keeps blast radius small: the Play SA has Play Console permissions; the push SA only needs the ability to mint OIDC tokens addressed to our webhook audience.

### 5.1 🧑 Create

Console → IAM & Admin → Service Accounts → **Create service account**

- **Name:** `repsaga-rtdn-pusher`
- **Description:** `Identity used by Pub/Sub to sign OIDC tokens on push delivery to the Supabase rtdn-webhook.`
- No project roles, no users. Done.

- [x] SA created (2026-04-22)

### 5.2 🧑 Grant the Pub/Sub service agent permission to act as this SA

Pub/Sub uses a Google-managed service agent (format `service-<project-number>@gcp-sa-pubsub.iam.gserviceaccount.com`) to impersonate the push-auth SA. Without this binding, push subscriptions with OIDC auth will fail to deliver.

Get your project number:

```bash
gcloud projects describe repsaga-prod --format="value(projectNumber)"
```

Then grant:

```bash
PROJECT_NUMBER=<paste-the-number>

gcloud iam service-accounts add-iam-policy-binding \
  repsaga-rtdn-pusher@repsaga-prod.iam.gserviceaccount.com \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project=repsaga-prod
```

If you see `NOT_FOUND: Service account service-XXXX@gcp-sa-pubsub.iam.gserviceaccount.com does not exist`, it means the Pub/Sub service agent hasn't been auto-provisioned yet. Force it:

```bash
gcloud beta services identity create \
  --service=pubsub.googleapis.com \
  --project=repsaga-prod
```

Then re-run the `add-iam-policy-binding` above.

- [x] Binding granted (2026-04-22)

### 5.3 🧑 Verify

```bash
gcloud iam service-accounts get-iam-policy \
  repsaga-rtdn-pusher@repsaga-prod.iam.gserviceaccount.com \
  --project=repsaga-prod
```

Expected: a binding for `roles/iam.serviceAccountTokenCreator` with a `gcp-sa-pubsub` member.

- [x] Verified (2026-04-22)

---

## Phase 6 — Grant the Play API service account access to the RepSaga app

> **Note on flow change:** Google deprecated the "link GCP project to Play Console" step around 2024. The new canonical flow is to invite the SA email directly as a Play Console user. No linking required.
> Source: [Bernardo do Amaral Teodosio — "You no longer need to have a GCP project associated with your Google Play Developer Account"](https://medium.com/@berteodosio/you-no-longer-need-to-have-a-gcp-project-associated-with-your-google-play-developer-account-to-c81e75ee1aff) and [Play Developer API Getting Started](https://developers.google.com/android-publisher/getting_started).

### 6.1 🧑 Invite the SA as a Play Console user

1. Play Console → left sidebar → **Users and permissions**
2. Click **Invite new users**
3. Email address: `repsaga-play-api@repsaga-prod.iam.gserviceaccount.com`
4. **Account permissions (cross-app tab):** leave all unchecked
5. **App permissions:** **Add app** → select **RepSaga** (`com.repsaga.app`)
6. For RepSaga, check these 3 only:
   - ✅ View app information and download bulk reports
   - ✅ View financial data, orders, and cancellation survey responses
   - ✅ Manage orders and subscriptions
   - ❌ Leave everything else off
7. **Invite user** → confirm

Wait ~60 seconds for propagation before any `validate-purchase` smoke test.

- [x] SA invited with RepSaga app permissions (2026-04-22)

### 6.2 🧑 Verify SA key is valid

From PowerShell:

```
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\Users\caiol\secrets\repsaga-prod-a558218af29e.json"
gcloud auth application-default print-access-token
```

Expected: long JWT string, exit 0. Errors mean the SA key file is malformed or the SA is disabled.

- [x] Verified SA auth produces a token (2026-04-22)

---

## Phase 7 — Create Pub/Sub topic + push subscription

### 7.1 🧑 Create the topic

```bash
gcloud pubsub topics create repsaga-rtdn --project=repsaga-prod
```

- [x] Topic created (2026-04-22)

### 7.2 🧑 Grant Play permission to publish to the topic

The Google-managed Play notifications identity is a fixed, documented email:

```bash
gcloud pubsub topics add-iam-policy-binding repsaga-rtdn \
  --member="serviceAccount:google-play-developer-notifications@system.gserviceaccount.com" \
  --role="roles/pubsub.publisher" \
  --project=repsaga-prod
```

- [x] Play granted publisher (2026-04-22)

### 7.3 🧑 Create the push subscription with OIDC auth

```bash
gcloud pubsub subscriptions create repsaga-rtdn-push \
  --topic=repsaga-rtdn \
  --push-endpoint=https://dgcueqvqfyuedclkxixz.supabase.co/functions/v1/rtdn-webhook \
  --push-auth-service-account=repsaga-rtdn-pusher@repsaga-prod.iam.gserviceaccount.com \
  --push-auth-token-audience=https://dgcueqvqfyuedclkxixz.supabase.co/functions/v1/rtdn-webhook \
  --ack-deadline=10 \
  --min-retry-delay=10s \
  --max-retry-delay=600s \
  --project=repsaga-prod
```

Critical: the `--push-auth-token-audience` value MUST exactly equal the value of the Supabase secret `RTDN_PUBSUB_AUDIENCE`. The webhook verifier rejects tokens whose `aud` claim doesn't match.

- [x] Push subscription created (2026-04-22)

### 7.4 🧑 Verify

```bash
gcloud pubsub topics describe repsaga-rtdn --project=repsaga-prod
gcloud pubsub subscriptions describe repsaga-rtdn-push --project=repsaga-prod
gcloud pubsub topics get-iam-policy repsaga-rtdn --project=repsaga-prod
```

Expected:

- Topic exists with correct name
- Subscription points at the correct push endpoint and audience
- IAM policy on topic includes `google-play-developer-notifications@system.gserviceaccount.com` as `roles/pubsub.publisher`

- [ ] Verified

---

## Phase 8 — Point Play Console at the new topic

### 8.1 🧑 Set the topic in Play Console

1. Play Console → **Monetize** → **Monetization setup**
2. Scroll to **Real-time developer notifications**
3. **Topic name** field: `projects/repsaga-prod/topics/repsaga-rtdn`
   - Must be the fully-qualified form with `projects/.../topics/...`
4. Click **Save**

Play validates that `google-play-developer-notifications@system.gserviceaccount.com` has publish permission on that topic before accepting. If Save errors, re-check Phase 7.2.

- [x] Topic saved in Play Console (2026-04-22)

### 8.2 🧑 Send a test notification

On the same page, click **Send test notification** (button appears once a topic is saved).

Expected within ~10s:

- **Pub/Sub metrics** (Console → Pub/Sub → Subscriptions → `repsaga-rtdn-push` → Metrics tab): 1 ack'd message, 0 nacks
- **Supabase Edge Function logs** for `rtdn-webhook`: a structured log like `{ "success": true, "test": true }`

**View logs:**

```bash
npx supabase functions logs rtdn-webhook --project-ref dgcueqvqfyuedclkxixz
```

- [x] Test notification delivered + logged (2026-04-22, 200 response, user-agent APIs-Google)

---

## Phase 9 — Update Supabase Edge Function secrets

Two of the three Edge Function secrets must be overwritten with new-project values. The third (`RTDN_PUBSUB_AUDIENCE`) doesn't change — the Edge Function URL is unchanged.

### 9.1 🤖 Claude runs these (after user confirms the SA JSON path)

```bash
# Overwrite service account JSON with the new key
npx supabase secrets set \
  --project-ref dgcueqvqfyuedclkxixz \
  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON="$(cat <path-to-new-repsaga-play-api.json>)"

# Package name (may already be com.repsaga.app from earlier rebrand — set anyway to be explicit)
npx supabase secrets set \
  --project-ref dgcueqvqfyuedclkxixz \
  GOOGLE_PLAY_PACKAGE_NAME=com.repsaga.app

# Confirm audience is correct (idempotent; setting same value does nothing harmful)
npx supabase secrets set \
  --project-ref dgcueqvqfyuedclkxixz \
  RTDN_PUBSUB_AUDIENCE=https://dgcueqvqfyuedclkxixz.supabase.co/functions/v1/rtdn-webhook
```

User provides absolute path of downloaded JSON key; Claude executes all three.

- [x] Secrets overwritten (2026-04-22; all 3 digests confirmed in `secrets list`)

### 9.2 🤖 Redeploy Edge Functions to pick up new env

Edge Function secrets are injected at cold-start. Forcing a redeploy guarantees the next invocation uses the new values.

```bash
npx supabase functions deploy validate-purchase --project-ref dgcueqvqfyuedclkxixz
npx supabase functions deploy rtdn-webhook --project-ref dgcueqvqfyuedclkxixz
```

- [x] Functions redeployed (2026-04-22; validate-purchase + rtdn-webhook)

### 9.3 🧑 Verify

```bash
npx supabase secrets list --project-ref dgcueqvqfyuedclkxixz
```

Expected: all three secrets present with non-empty hashes.

- [x] Verified (2026-04-22)

---

## Phase 10 — Supabase Vault check (reconciliation cron)

The pg_cron reconciler reads `edge_functions_url` + `service_role_key` from Vault. Neither changes with the GCP rename (they point at Supabase, not Google). Still, verify:

### 10.1 🧑 Run in Supabase SQL editor

```sql
SELECT name, decrypted_secret IS NOT NULL AS present
  FROM vault.decrypted_secrets
 WHERE name IN ('edge_functions_url', 'service_role_key');
```

Expected: 2 rows, both `present = true`. If not, open `docs/phase-16a-setup.md` §2 and set them.

- [x] Both Vault secrets present (2026-04-22)

---

## Phase 11 — End-to-end smoke test

### 11.1 🧑 Re-send Play test notification (confirms RTDN path after redeploy)

Same as Phase 8.2. Expect fresh 200 in Edge Function logs.

- [x] Post-redeploy test notification successful (2026-04-22)

### 11.2 🧑 `validate-purchase` dry-run

Until the Flutter client is wired (Phase 16b), the only way to test validate-purchase is with a real license-tester purchase token. Defer this test to 16b unless you already have a token; the Phase 8 RTDN test is sufficient proof that Play → Pub/Sub → Edge Function wiring is alive.

- [ ] (optional) validate-purchase smoke test with license-tester token

---

## Phase 12 — Update `docs/phase-16a-setup.md`

🤖 Once Phase 11 is green, Claude will update:

- Hardcoded examples referencing the old GCP project ID → `repsaga-prod`
- Topic names (`repsaga-rtdn`) — already correct in current doc
- Service account name — already correct

This is a docs-only PR, fast to land per project convention.

- [x] Docs updated (2026-04-22; phase-16a-setup.md §1.3 flow + cross-ref)

---

## Phase 13 — Decommission old GCP project

Nothing depends on the old project once Phase 11 passes. Delete it immediately.

### 13.1 🧑 Shut down the old project

1. Console → project picker → switch to OLD project
2. IAM & Admin → **Settings**
3. **Shut down** button at top
4. Type the project ID to confirm → Shut down

**30-day recovery window:** for 30 days you can undelete via `gcloud projects undelete <id>`. After that, the project ID is released and resources are unrecoverable. Fine for our case.

- [x] Old project `gymbuddy-app-proj` shut down (2026-04-22)

### 13.2 🧑 Delete the old SA JSON key file

If the old project's `*-play-api.json` file is still on disk, delete it. Inert once the project is shut down, but no reason to keep it around.

- [x] Old SA JSON deleted (2026-04-22)

---

## Phase 14 — Update WIP.md checklist

🤖 Claude flips these in `docs/WIP.md`:

- [x] **GCP project display name** — superseded by fresh-project creation
- [x] **Pub/Sub topic** — recreated as `repsaga-rtdn`
- [x] **Pub/Sub push subscription** — recreated as `repsaga-rtdn-push`
- [x] **Supabase Edge Function secret** `GOOGLE_PLAY_PACKAGE_NAME` → `com.repsaga.app`

---

## Progress notes

Use this space to log issues, decisions, or deviations encountered during execution:

-
-
-
