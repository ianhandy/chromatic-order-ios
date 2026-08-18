# App Store Connect automation

`app_store_connect.py` is a zero-dependency helper for Kromatika releases. It
uses Apple's official App Store Connect API for status, Game Center inventory,
build association, and App Review submissions. It uses Apple's `altool` through
Xcode for IPA validation and upload.

## Credentials

Create a least-privilege App Store Connect API key and keep the downloaded `.p8`
file outside this repository. Export its values only in the shell that runs the
tool:

```sh
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_PRIVATE_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"
```

An individual API key can omit `ASC_ISSUER_ID` for API commands. Binary upload
uses a team key and expects the key in one of the locations supported by
`altool`, including `~/.appstoreconnect/private_keys/`.

Never commit the `.p8` file or print its contents.

## Common workflow

```sh
# Read-only account snapshot
tools/app_store_connect.py status
tools/app_store_connect.py game-center
tools/app_store_connect.py in-app-purchases

# Preview every write before applying it
tools/app_store_connect.py ensure-streak-leaderboard
tools/app_store_connect.py ensure-full-version-iap
tools/app_store_connect.py attach-build --version 1.0.0 --build 12

# Validate, then upload an exported IPA
tools/app_store_connect.py upload --ipa build/export/ChromaticOrder.ipa --validate-only --apply
tools/app_store_connect.py upload --ipa build/export/ChromaticOrder.ipa --apply

# Attach the processed build
tools/app_store_connect.py attach-build --version 1.0.0 --build 12 --apply

# Review the plan, then explicitly send it to App Review
tools/app_store_connect.py submit --version 1.0.0
tools/app_store_connect.py submit --version 1.0.0 --apply --confirm-submit
```

All mutating commands are dry-run by default. The final App Review action has a
second guard, `--confirm-submit`. The helper does not create API keys, store
credentials, change pricing, or release an approved version. The full-version
helper creates only the base non-consumable resource; because its product ID and
type become permanent, inspect the dry run before adding `--apply`. Localization,
price, and the App Review screenshot stay explicit release steps.

The leaderboard helper creates only the base leaderboard resource when it is
missing. Its localization and leaderboard-version review association remain
visible App Store Connect steps because those are release-specific metadata.
