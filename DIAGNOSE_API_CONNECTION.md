# ElevenLabs API Connection - Troubleshooting Guide

## Current Connection Model
BitBinder no longer uses Firebase as a fallback transport. The app should call its configured AI service path directly through the current app service layer.

## What to Check
1. Confirm the widget is invoking the expected service in `thebitbinder/Services/`.
2. Verify the API key, agent ID, and request payload expected by the active service.
3. Review Xcode console output for request failures, timeouts, or decoding issues.
4. Confirm the device or simulator has network access when using remote AI services.

## Common Failure Modes
- **401 / 403**: invalid credentials or mismatched agent access.
- **404**: wrong endpoint or agent identifier.
- **429**: rate limiting from the provider.
- **5xx / timeout**: upstream service instability or connectivity problems.
- **Empty response**: payload shape changed or response parsing needs an update.

## Recommended Debug Flow
1. Reproduce the issue in the app.
2. Inspect the exact service handling the request.
3. Compare request and response data with the provider's current API docs.
4. Fix the service integration rather than introducing a Firebase proxy.

## Status
This document was simplified to remove obsolete Firebase Cloud Function fallback instructions.
