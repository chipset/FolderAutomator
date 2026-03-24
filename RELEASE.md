# Release Notes

## Local packaging

Run:

```bash
./scripts/package-apps.sh
```

This builds release `.app` bundles and zip archives into `dist/`.

## Still external to the repo

These release steps require Apple credentials and cannot be completed fully offline in this workspace:

- Developer Team selection for production signing
- Notarization with `notarytool`
- Stapling notarization tickets
- Mac App Store sandbox review and entitlement tuning

## Recommended next release hardening

- Add real app icons and branding assets
- Add integration tests around FSEvents and Finder-tag AppleScript behavior
- Add broader UI tests for drag-and-drop setup, import/export, and undo flows
- If you want Mac App Store distribution, replace path-based fallbacks with a fully sandboxed bookmark and entitlement model
