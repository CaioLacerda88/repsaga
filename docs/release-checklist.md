# Release Checklist

Everything the user must do exactly once before tagging the first release.
The pipeline is inert until these secrets exist and a `v*` tag is pushed.

---

## 1. GitHub Repository Secrets

Add each secret at **Settings > Secrets and variables > Actions > New repository secret**.

| Secret name | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded upload keystore (`.jks`). See section 2. |
| `ANDROID_KEY_ALIAS` | The alias you chose when generating the key (`upload` if you followed section 2). |
| `ANDROID_KEY_PASSWORD` | Password for the key entry inside the keystore. |
| `ANDROID_STORE_PASSWORD` | Password for the keystore file itself. |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Play service account JSON (full file contents). See section 3. Without this secret the pipeline still produces the GitHub release but skips the Play upload. |
| `SENTRY_DSN` | The DSN string from your Sentry project. See section 4. Leave empty to disable Sentry in production (not recommended for launch). |
| `PROD_SUPABASE_URL` | Hosted Supabase project URL, e.g. `https://xxxxxxxxxxxx.supabase.co`. |
| `PROD_SUPABASE_ANON_KEY` | The `anon` / `public` key — NOT the `service_role` key. |

---

## 2. Generating the Upload Keystore

Run once on your local machine. Store the `.jks` and both passwords somewhere safe (a password manager or secure note). If you lose the keystore you cannot update the app on Play.

```bash
# Generate the keystore
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload

# Base64-encode it for the GitHub secret (Linux/macOS)
base64 -w0 upload-keystore.jks
# On macOS use: base64 -i upload-keystore.jks | tr -d '\n'
```

Copy the full base64 output (one long string, no newlines) into the `ANDROID_KEYSTORE_BASE64` secret.

Add the alias you used (`upload`), the key password, and the keystore password as their respective secrets.

The keystore file itself must NEVER be committed. It is gitignored via `android/keystore/` and `**/*.jks` in the root `.gitignore`.

### Play App Signing

Google Play wraps your upload key in their App Signing system. When creating the app in Play Console, choose "Use Google-managed key" or "Use upload key" — follow the Play Console wizard. Your upload keystore is what you submit; Google re-signs the distributed APK/AAB with their signing key.

---

## 3. Google Play Setup

1. Create the app in **Google Play Console** (package name: `com.repsaga.app`).
2. Enroll in **Play App Signing** (Settings > App integrity). Follow the wizard.
3. Upload a signed AAB at least once manually to the internal track to initialize the app's release history (Play requires at least one uploaded artifact before the API upload will work).
4. Create a **service account**:
   - Go to **Google Play Console > Setup > API access**.
   - Link to a Google Cloud project (or create one).
   - Click **Create new service account**.
   - In Google Cloud IAM, grant the service account the **Service Account User** role.
   - Back in Play Console, grant the service account **Release manager** permissions on the app (or a narrower set: Releases > Release to internal testing is sufficient for the pipeline's `internal` track upload).
   - Download the JSON key for the service account.
5. Paste the entire JSON key file contents into the `PLAY_SERVICE_ACCOUNT_JSON` secret.

The pipeline uploads to the `internal` track with `status: completed`. Promotion to alpha, beta, or production is a manual step in Play Console after QA sign-off.

---

## 4. Sentry DSN

1. Log in to [sentry.io](https://sentry.io) (or your self-hosted Sentry).
2. Create a project: Platform = **Flutter**.
3. Copy the **DSN** from the project settings (Settings > Projects > your project > Client Keys).
   It looks like `https://abc123@o123456.ingest.sentry.io/789`.
4. Add it as the `SENTRY_DSN` secret.

### One-time manual Sentry verification (required before launch)

Build a staging APK with a real DSN, install it, and trigger a deliberate exception:

```dart
// Somewhere reachable during manual testing only:
throw Exception('sentry-test-exception');
```

Confirm in Sentry:
- The event appears with the correct environment (`prod` or `dev`).
- No email addresses appear in the event payload (the `scrubEventPii` / `beforeBreadcrumb` path in `lib/core/observability/sentry_init.dart` must have run).
- Stack frames show obfuscated symbols. Then symbolicate: see section 6.

Remove the deliberate throw before tagging the release.

---

## 5. Production Supabase Credentials

- **URL**: in the Supabase dashboard, Settings > API > Project URL.
- **Anon key**: Settings > API > `anon` `public` key.

Use the `anon` key only. The `service_role` key bypasses RLS and must never reach a client build.

---

## 6. Release Procedure

```bash
# 1. Ensure main is clean and CI is green.
git checkout main
git pull

# 2. Tag the release.  Use semver.
#    Stable:        v0.1.0
#    Beta pre-release: v0.1.0-beta.1
#    Alpha:         v0.1.0-alpha.1
git tag v0.1.0
git push --tags
```

The pipeline then:
1. Decodes the keystore and writes `android/key.properties`.
2. Writes the real prod `.env` (Supabase + Sentry credentials).
3. Runs `flutter pub get` + codegen.
4. Builds the release AAB (`--obfuscate --split-debug-info`) and signed split APKs.
5. If `PLAY_SERVICE_ACCOUNT_JSON` is set: uploads the AAB to the Play internal track.
6. Creates a GitHub release with the signed APKs + `debug-info.zip` attached.

alpha/beta tags produce a GitHub pre-release. All other `v*` tags produce a full release.

### Post-release: symbolicate a crash stack

Download `debug-info.zip` from the GitHub release, then:

```bash
# Unzip the symbols
unzip debug-info.zip -d debug-info/

# Use Flutter's symbolizer. `--split-debug-info` writes the symbol files FLAT
# in build/debug-info/ (no per-arch subdirectory), named by architecture:
#   app.android-arm64.symbols / app.android-arm.symbols / app.android-x64.symbols
flutter symbolize \
  --debug-info debug-info/app.android-arm64.symbols \
  --input /path/to/crash-stack.txt
```

Pick the `.symbols` file matching the crashing architecture (`app.android-arm64.symbols` for arm64-v8a, `app.android-arm.symbols` for armeabi-v7a, `app.android-x64.symbols` for x86_64).

---

## 7. What happens without the secrets

The pipeline will fail loud rather than silently:

- Missing `ANDROID_KEYSTORE_BASE64`: the **Inject release keystore** step fails immediately with a clear `::error::` (it guards on the empty secret + an empty decoded `.jks`) — no artifact is produced. Missing `ANDROID_KEY_*` / `ANDROID_STORE_PASSWORD` (but keystore present): `key.properties` is written with empty passwords, so the build fails at the **AAB/APK signing step** when Gradle can't unlock the keystore. Either way: fails loud, no signed artifact.
- Missing `PROD_SUPABASE_URL` / `PROD_SUPABASE_ANON_KEY`: the `.env` will have empty values; `dotenv.env['SUPABASE_URL']!` will throw at app startup.
- Missing `PLAY_SERVICE_ACCOUNT_JSON`: the Play upload step is skipped (not a failure); the GitHub release is still created.
- Missing `SENTRY_DSN`: Sentry is skipped (`initSentryAndRun` no-ops on an empty DSN); the release still ships but crash reporting is inactive.

The app cannot be released without the keystore, Supabase URL, and Supabase anon key. Those are non-optional.
