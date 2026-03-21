# Anonymous Sessions

## Overview
BitBinder can support anonymous or temporary conversation flows without Firebase. Any guest-session behavior should now be implemented with the app's current models, local persistence, and active service abstractions.

## Current Guidance
- Store temporary conversations locally unless the current backend explicitly supports guest ownership.
- If a user later signs in, migrate ownership through the app's active service layer.
- Use local cleanup rules or backend policies for session expiration.
- Avoid Firebase-specific rules, APIs, or console workflows.

## Recommended Checks
1. Verify anonymous conversations can be created without a sign-in dependency.
2. Confirm local persistence behavior matches the intended user experience.
3. Validate any migration path from guest to signed-in state in the live service implementation.

## Status
This document was rewritten to remove obsolete Firebase-specific session guidance.
