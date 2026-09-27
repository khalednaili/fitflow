---
name: deploy
description: Deploy the FitFlow Flutter web app and/or Cloud Functions to Firebase Hosting on the "reservationgym" project. Triggers on phrases like "deploy", "deploy the web app", "deploy functions", "ship this", "push to production", or similar. Always confirms scope with the user before running the real deploy.
version: 1.0.0
---

# Deploy FitFlow (Firebase Hosting + Functions)

## Overview

This repo deploys to a single Firebase project:

| Target      | Command                                       | Config                          |
|-------------|------------------------------------------------|----------------------------------|
| Web hosting | `flutter build web --release` then `firebase deploy --only hosting` | `firebase.json` → `hosting`, public dir `build/web` |
| Functions   | `firebase deploy --only functions`             | `functions/index.js`, `functions/package.json` |
| Firestore   | `firebase deploy --only firestore`             | `firestore.rules`, `firestore.indexes.json` |
| Storage     | `firebase deploy --only storage`               | `storage.rules` |

Firebase project: `reservationgym` (see `.firebaserc`). Confirm `firebase projects:list` shows it as `(current)` before deploying — do not switch projects without asking.

## Before deploying: always confirm with the user

Never run a real `firebase deploy` without explicit confirmation. Ask (via the ask_user tool if available):
- **What to deploy**: hosting / functions / firestore rules / storage rules (any combination).
- **What code state**: current working tree as-is (including uncommitted changes), or committed-only (stash uncommitted changes first).

Only proceed with the actual deploy after the user confirms.

## Deploy steps

1. **Check git state** — `git status --porcelain` and `git branch --show-current`. Report uncommitted changes to the user as part of the confirmation step; don't silently commit or discard anything.
2. **Web hosting**:
   - Run `flutter build web --release` (expect ~20-30s; use a 120-180s initial_wait).
   - Then `firebase deploy --only hosting`.
   - Report the live Hosting URL from the CLI output (`https://reservationgym.web.app`) and the console link.
3. **Functions** (only if requested):
   - Sanity-check `functions/index.js` for syntax errors is unreliable locally (`node -e "require('./index.js')"` will falsely fail on 2nd-gen Storage triggers that need `FIREBASE_CONFIG`/bucket options set — this is expected locally and NOT a real bug). Prefer letting `firebase deploy` itself validate via its analysis phase.
   - Run `firebase deploy --only functions` (use 120-240s initial_wait; the analysis + upload + build phase is slow).
   - **Known project constraints to check if a deploy fails**:
     - **Region mismatch for Storage triggers**: `onObjectFinalized`/`onObjectDeleted` (2nd-gen Cloud Storage triggers) must run in the **same region as the default Cloud Storage bucket**, not necessarily the same region as other functions. This project's other functions run in `us-central1`, but its default bucket is in `us-east1`. Check bucket region with `gsutil ls -L -b gs://reservationgym.appspot.com | grep -i location`, and pass `{ region: '<bucket-region>' }` as the first arg to `onObjectFinalized`/`onObjectDeleted` if you hit: `Error: A function in region X cannot listen to a bucket in region Y`.
     - **Blaze plan requirement**: Eventarc-based triggers (2nd-gen `onDocumentWritten`, `onObjectFinalized`, `onObjectDeleted`, etc.) require the project to be on the **Blaze** (pay-as-you-go) plan, not the free Spark plan. If deploy fails with `Extensions require the Blaze plan, but project ... is not on the Blaze plan`, **stop and tell the user** — linking a billing account is a financial decision only they can make (console link is in the error message). Do not attempt to work around it.
4. **Firestore/Storage rules** (only if requested): `firebase deploy --only firestore` / `firebase deploy --only storage`.

## After deploying

Report:
- Which targets were deployed.
- The live URL(s) and console link.
- Any targets that were skipped/blocked, and why (e.g. "functions not deployed — project needs the Blaze plan").
