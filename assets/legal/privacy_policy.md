# Privacy Policy

**Last updated: 2026-06-04**

This Privacy Policy describes how RepSaga ("we", "us", or "our") collects, uses, and protects your information when you use the RepSaga mobile and web application (the "App"). RepSaga's primary market is Brazil and the App is operated in compliance with the Lei Geral de Proteção de Dados (LGPD, Lei nº 13.709/2018). Users in the European Economic Area (EEA) and the United Kingdom are additionally protected by the General Data Protection Regulation (GDPR) and UK GDPR.

## 1. Who We Are

RepSaga is a fitness tracking application that helps you log workouts, track personal records, and manage your exercise library. If you have questions about this policy, contact us at **support@repsaga.app**. For data-protection-specific questions, see Section 12 (Data Protection Officer).

## 2. Information We Collect

We collect only the information you provide directly and a small number of in-app events used to improve the App (see "Usage Events" below). RepSaga does not use advertising SDKs, ad networks, or analytics services that share your data with advertisers. We use Sentry to receive crash reports when the App encounters an unhandled error — see Section 5.

### Account Information
- **Email address** — used for authentication and account recovery.
- **Password** — stored as a hashed value by Supabase Auth. We never see or store your plain-text password.
- **Google OAuth identifier** — if you sign in with Google, we receive a unique identifier and your email address from Google.

### Profile Information
- Display name
- Weight unit preference (kilograms or pounds)
- Locale preference (`en` or `pt`)
- Training goals (e.g. weekly workout frequency)
- **Body weight (`bodyweight_kg`)** — *sensitive personal data* under LGPD Art. 11 / GDPR Art. 9 (data concerning health). Collection is **opt-in**: the field is omittable and can be deleted at any time. See Section 2a below.
- **Gender (`male`, `female`, or `other`)** — *sensitive personal data* under LGPD Art. 11 / GDPR Art. 9. Collection is **opt-in**. Used solely to select the per-lift strength-tier reference table that calibrates XP for resistance exercises (male-tier tables are sourced from Symmetric Strength reference data; female-tier tables from strengthlevel.com). If you leave gender unset or choose `'other'`, the App falls back to the male-tier table for now — this is a documented, conservative default and has no other effect on your account. See Section 2a below.
- **Avatar photo (`avatar_url`)** — optional. If you upload one, it is stored in a **private Supabase Storage bucket** and served to the App via short-lived signed URLs (refreshed by the App; typical link lifetime up to 1 year, regenerated on demand). The photo is never publicly accessible.

### Fitness Data
- Workout history: exercises, sets, reps, weight, dates, notes, and workout duration
- Customizations you make to the exercise library
- Personal records detected by the App

### Derived RPG Data
RepSaga calculates progression data from your workout history. We disclose this as **processed data** so you can request, correct, or delete it:

- Cumulative experience points (XP) totals per body part (`body_part_progress`)
- Body-part ranks (1–99 scale) and rank-up history
- Per-exercise peak loads (`exercise_peak_loads`)
- RPG class and earned titles (`earned_titles`)
- A polymorphic XP event log (`xp_events`) that records the breakdown components of each XP gain

All derived data is regenerated from workout history and is deleted along with the underlying workout data when you delete your account (Section 7).

### Subscription / Purchase Data (Launch Phase paywall)

When the App's paywall launches, premium subscriptions will be processed through Google Play Billing. We will receive only:

- `product_id` — the SKU you purchased
- `purchase_token` — the opaque token Google Play issues to verify the purchase
- Subscription `state` — active / on-hold / cancelled / expired / grace-period
- Billing window — period start and period end timestamps

**We never receive your card number, CVV, billing address, or any other payment instrument data.** Google Play handles payment collection end-to-end under its own privacy policy.

### Usage Events

To understand how the App is used and improve reliability, we log a small, fixed set of in-app events to our own `analytics_events` table alongside your other data. The current event set is:

`onboarding_completed`, `workout_started`, `workout_discarded`, `workout_finished`, `week_plan_saved`, `week_complete`, `add_to_plan_prompt_responded`, `workout_sync_queued`, `workout_sync_succeeded`, `workout_sync_failed`, `first_rank_up`, `post_session_cinematic_shown`, `share_card_exported`, `title_unlocked`, `session_zero_xp`.

Each event records the action and a small payload of structured parameters (e.g. workout duration, set counts, body part of a first rank-up, the earned title slug). Some payloads include internal app identifiers such as `routine_id` or `title_slug` so we can correlate funnel steps. **Events never contain your email address, display name, workout notes, or any free-text input.** All event rows are tied to your account via foreign key and are deleted by `CASCADE` when you delete your account (Section 7).

A separate `account_deletion_events` row is written when you delete your account so we can confirm the deletion completed — it is not tied to your `user_id` and contains no identifying data.

### 2a. Sensitive Personal Data — Heightened Consent

Body weight and gender are classified as **sensitive personal data** ("data concerning health") under LGPD Art. 11 and GDPR Art. 9. They are collected only with your **explicit, granular opt-in** through in-app toggles. You can withdraw consent for either field at any time, which removes the value from your profile and the App reverts to the documented fallback behavior:

- **Body weight withdrawn:** XP accuracy is reduced for bodyweight exercises (push-ups, pull-ups, dips, etc.), because the App can no longer include your own mass in the load calculation. This is the **only** consequence. All other features continue to work.
- **Gender withdrawn:** the App reverts to the male-tier reference table for strength-tier calibration — the same fallback used when `gender = 'other'`.

The in-app opt-in surface is delivered by a separate update (PR 2 of the legal compliance series).

## 3. How We Collect Information

All information is collected directly from the App based on actions you take (signing up, logging workouts, editing your profile, etc.). We do not track your location or device activity. The usage events described in Section 2 are collected to improve the App and are the only form of usage tracking.

## 4. How Your Data Is Stored

Your data is stored on Supabase infrastructure:

- **Database:** PostgreSQL with row-level security — each user can only access their own data.
- **Storage (avatars):** private Supabase Storage bucket; served only via signed URLs as described in Section 2.
- **In transit:** encrypted via TLS.
- **At rest:** encrypted by Supabase at the storage layer.

Supabase may process data in the regions where it operates. International transfers are addressed in Section 9. See [supabase.com/privacy](https://supabase.com/privacy) for Supabase's own policies and [supabase.com/dpa](https://supabase.com/dpa) for the Data Processing Addendum.

## 4a. Lawful Bases for Processing

Under LGPD Art. 6 (and the parallel GDPR Art. 6 §1 and Art. 9 §2 where applicable), each category of data is processed on the lawful basis stated below:

| Data category | LGPD basis | GDPR basis | Purpose |
| --- | --- | --- | --- |
| Email, password, OAuth identifier | Art. 6 V (contract performance) | Art. 6 §1(b) | Authenticate you and provide the service |
| Display name, locale, weight-unit preference | Art. 6 V (contract performance) | Art. 6 §1(b) | Render the App in your language and units |
| Workout history, exercise customizations, personal records | Art. 6 V (contract performance) | Art. 6 §1(b) | Provide the core tracking service you signed up for |
| Derived RPG data (XP, ranks, peak loads, classes, titles) | Art. 6 V (contract performance) | Art. 6 §1(b) | Provide the progression features you signed up for |
| **Body weight** | **Art. 11 §I(a) (explicit consent for sensitive data)** | **Art. 9 §2(a) (explicit consent)** | Improve XP accuracy for bodyweight exercises |
| **Gender** | **Art. 11 §I(a) (explicit consent for sensitive data)** | **Art. 9 §2(a) (explicit consent)** | Select the strength-tier reference table for XP calibration |
| Avatar photo | Art. 7 I (consent) | Art. 6 §1(a) (consent) | Personalize your profile |
| Usage events (Section 2 list) | Art. 7 IX (legitimate interest) | Art. 6 §1(f) (legitimate interest) | Diagnose bugs, prioritize features, measure reliability. Balancing test documented and available on request. |
| Crash reports (Sentry) | Art. 7 IX (legitimate interest) | Art. 6 §1(f) (legitimate interest) | Diagnose and fix App crashes |
| Subscription data (Launch Phase) | Art. 6 V (contract performance) | Art. 6 §1(b) | Verify and provision your paid subscription |

For data processed on the basis of consent (body weight, gender, avatar), withdrawing consent is as easy as giving it: see Sections 2a, 6, and the in-app toggles delivered by PR 2.

## 5. Third Parties

RepSaga uses the following third-party services (data sub-processors):

- **Supabase** — hosting, authentication, database, and private object storage. Supabase is contractually bound by its Data Processing Addendum at [supabase.com/dpa](https://supabase.com/dpa), which includes Standard Contractual Clauses for international transfers.
- **Google (Google Sign-In)** — OAuth authentication only, if you choose to sign in with Google.
- **Google Play Billing** — payment processing for premium subscriptions (Launch Phase only). Google receives all payment-instrument data directly; RepSaga receives only the fields enumerated in Section 2.
- **Sentry** — crash reporting only. When the App encounters an unhandled error, a stack trace, the environment (OS, app version), and your account ID (no email, no name, no IP address) are sent to sentry.io so we can diagnose and fix the bug. You can disable this at any time in **Profile → Privacy → Send crash reports**. For Sentry's own policies, see [sentry.io/privacy](https://sentry.io/privacy/).

We do **not** use advertising networks. We do **not** sell your data. We do **not** share your fitness data with insurers, employers, or anyone else.

## 6. Your Rights

Under LGPD Art. 18 (and the parallel GDPR Articles 15–22 where applicable), you have the following rights regarding your personal data. Where an in-app mechanism is available, it is the fastest path. Where one is not yet available, we honor email requests with a declared service-level agreement (SLA) of **15 business days** from receipt at **dpo@repsaga.app** (response timeframe is informed by LGPD Art. 19 §1 and ANPD guidance).

| Right | LGPD | GDPR | How to exercise |
| --- | --- | --- | --- |
| **Confirmation of processing** | Art. 18 I | Art. 15 | Email `dpo@repsaga.app` (15 business days) |
| **Access** — receive a copy of your data | Art. 18 II | Art. 15 | Profile → Manage Data → Export. The in-app JSON export is delivered by a separate update (PR 3); until then, email `dpo@repsaga.app` and we will deliver the export within 15 business days |
| **Correction / rectification** | Art. 18 III | Art. 16 | Edit directly in Profile, or email `dpo@repsaga.app` |
| **Anonymization, blocking, or deletion of unnecessary or excessive data** | Art. 18 IV | Art. 17 | Email `dpo@repsaga.app` |
| **Erasure** — delete your account and all data | Art. 18 VI | Art. 17 | Profile → Manage Data → Delete Account (instant). See Section 7 |
| **Granular erasure** — delete individual sensitive fields without closing the account | Art. 18 IV | Art. 17 | **Body weight** and **avatar photo** can be deleted individually via Profile → Edit Profile. Gender can be cleared via Profile → Edit Profile. The full UI surface ships in PR 2 |
| **Data portability** — receive your workout history in a structured, machine-readable format | Art. 18 V | Art. 20 | Profile → Manage Data → Export. The in-app JSON export ships in PR 3; until then, email `dpo@repsaga.app` (15 business days) |
| **Information about data sharing** with public and private entities | Art. 18 VII | — | See Section 5 and Section 9; for additional detail email `dpo@repsaga.app` |
| **Information about the consequences of refusing consent** | Art. 18 VIII | — | See Sections 2a and 6 |
| **Withdrawal of consent** | Art. 18 IX | Art. 7 §3 | In-app toggles for body weight, gender, avatar, and crash reports. Withdrawal is as easy as giving consent and takes effect immediately |
| **Restriction of processing** | — | Art. 18 | Email `dpo@repsaga.app` |
| **Objection** to processing on legitimate-interest grounds (Section 4a) | — | Art. 21 | Email `dpo@repsaga.app` |
| **Lodge a complaint** with a supervisory authority | Art. 18 (via ANPD jurisdiction) | Art. 77 | Brazil: ANPD (Autoridade Nacional de Proteção de Dados), [gov.br/anpd](https://www.gov.br/anpd). EEA / UK: your national data protection authority |

## 7. Account Deletion

You can delete your account at any time through **Profile → Manage Data → Delete Account**, or by contacting `dpo@repsaga.app`. Deletion is permanent and cascades through every table tied to your `user_id`: workouts, sets, profile, derived RPG data (XP events, body-part progress, earned titles, peak loads), analytics events, and your avatar object in private storage.

All deletions complete within **30 days** of your request. This window is subject to Supabase's backup retention schedule — encrypted database backups may persist a short period after live deletion before being rotated out. For the current Supabase backup window, see [supabase.com/privacy](https://supabase.com/privacy). No backup is restored except for disaster recovery, and any restore that brings deleted data back will trigger a re-purge.

## 8. Children and Minimum Age

**RepSaga requires users to be at least 18 years old.** This threshold is set in alignment with LGPD Art. 14 (which requires verifiable parental or guardian consent for users under 18, infrastructure that RepSaga has not built). Users in the European Economic Area must additionally meet the GDPR Art. 8 §1 digital-services age, which we apply at 16 as a conservative floor.

If a user under 18 (or under 16 in the EEA) creates an account, the account will be terminated and all associated data deleted upon discovery or notification. If you believe a minor has provided us with personal information, contact `dpo@repsaga.app` and we will delete it.

Age confirmation at signup is enforced through an explicit checkbox in the signup flow (delivered by PR 2 of the legal compliance series).

## 9. International Users and Cross-Border Transfers

RepSaga is operated from Brazil with users in multiple jurisdictions. Your data may be processed in any region where Supabase operates its infrastructure to provide the service.

International transfers are governed by:

- **LGPD Art. 33** — Supabase, as our processor, is bound by a contract that ensures an adequate level of personal-data protection (Art. 33 II) and by your explicit acceptance of this Privacy Policy (Art. 33 VIII) for transfers required to perform the service contract (Art. 33 V).
- **GDPR Chapter V** — Supabase's Data Processing Addendum ([supabase.com/dpa](https://supabase.com/dpa)) incorporates the European Commission's **Standard Contractual Clauses** (Art. 46 §2(c)) as the transfer mechanism for processing outside the EEA.
- **UK GDPR** — the UK International Data Transfer Addendum (IDTA) where applicable.

You can request the relevant transfer-mechanism documentation by emailing `dpo@repsaga.app`.

## 10. Security Incidents and Breach Notification

In the event of a security incident that may involve risk or relevant damage to your personal data, RepSaga will notify the Autoridade Nacional de Proteção de Dados (ANPD) and affected users within the timeframe required by LGPD Art. 48 and ANPD regulation. For users protected by GDPR, the notification timeframe is the 72-hour window set by GDPR Art. 33 §1.

## 11. Changes to This Policy

We may update this Privacy Policy from time to time. When we do, we will update the "Last updated" date at the top of this document. For material changes — such as adding a new data category, a new sub-processor, or a change to the lawful basis for any processing — we will notify you via the App or by email before the changes take effect, and (where consent is the lawful basis) re-request your consent.

## 12. Data Protection Officer (Encarregado de Proteção de Dados)

In accordance with LGPD Art. 41, RepSaga has appointed a Data Protection Officer ("Encarregado") to act as the channel between you, RepSaga, and the Autoridade Nacional de Proteção de Dados (ANPD):

- **Name:** Caio Lacerda
- **Email:** **dpo@repsaga.app**

The DPO is available to:

- receive complaints and communications from data subjects, provide clarifications, and take action (LGPD Art. 41 §2 I);
- receive communications from the ANPD and take action (LGPD Art. 41 §2 II);
- guide RepSaga employees and contractors on data-protection practices (LGPD Art. 41 §2 III).

For GDPR purposes, the same contact serves as the privacy-policy point of contact under Art. 13 §1(b). RepSaga is not currently required to appoint a GDPR Art. 37 Data Protection Officer, but you can address GDPR-scope requests to the same email and they will be handled under the SLA in Section 6.

## 13. Contact

General questions, concerns, or requests: **support@repsaga.app**.
Data-protection requests (LGPD / GDPR / UK GDPR rights, sub-processor questions, transfer-mechanism documentation, breach inquiries): **dpo@repsaga.app**.
