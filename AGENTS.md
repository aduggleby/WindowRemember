# WindowRemember maintenance

- Preserve all user layouts and diagnostic history across builds, releases, and installations.
- Install local builds with `scripts/install-app.sh`. It creates private before/after shutdown backups before replacing only the application bundle. If backup or shutdown verification fails, stop the installation and fix the failure.
- Never delete, truncate, replace, or automatically prune logs, archives, deployment backups, or layouts in Application Support. Log rotation must use unique filenames and preserve older archives. Any intentional deletion requires the user's explicit request.
- Keep private logs, window titles, layout files, monitor identifiers, and local deployment backups outside the repository and release packages.
- Run `DiagnosticRetentionTests` when changing diagnostics or deployment behavior.
