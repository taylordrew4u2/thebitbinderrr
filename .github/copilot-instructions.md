When working in this repository:

- Treat user-created data as high-stakes.
- Never introduce silent delete behavior.
- Never introduce silent failure behavior around persistence.
- Never assume a save succeeded without checking the real code path.
- Audit create, update, save, delete, import, export, migration, sync, reset, and cleanup paths before changing them.
- Prefer explicit destructive actions with confirmation and recovery over implicit deletion.
- Preserve existing user data during refactors and migrations.
- Add or update tests for any persistence-related change.
- If a data-loss risk cannot be fully eliminated, state it explicitly.
- Remove dead code, duplicate persistence helpers, stale migration code, and obsolete delete paths when safe.
- Do not invent architecture that does not exist in the codebase.
- Reference the actual files, models, and save/delete/sync logic found in the project.
