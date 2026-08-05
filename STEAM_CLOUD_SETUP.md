# Steam Auto-Cloud setup for Towering Tower

The game now keeps cloud-worthy progression in a dedicated `user://steam_cloud/` directory while leaving machine-specific display and audio settings outside it.

## Files to synchronize

- `meta_progression.cfg` — metacurrencies, upgrades, unlocked cosmetics, and equipped cosmetics.
- `CrowManSaveFile.tres` — legacy save-resource support; currently not active in gameplay, but prepared for migration if it is re-enabled.

Existing `user://meta_progression.cfg` and `user://CrowManSaveFile.tres` files are read once and copied into the new directory. They are retained as recovery backups.

Do **not** synchronize `user://settings.cfg`; resolution, fullscreen, VSync, and local audio choices can be machine-specific.

## Steamworks Auto-Cloud configuration

In **Steamworks App Admin → Steam Cloud**:

1. Set a small per-user quota, such as 1 MB and 10 files. The current saves are tiny.
2. Add a Windows Auto-Cloud root:
   - Root: `WinAppDataRoaming`
   - Subdirectory: `Godot/app_userdata/Towering Tower/steam_cloud`
   - Pattern: `*`
   - OS: Windows
   - Recursive: disabled
3. If the macOS build will ship, configure the corresponding Godot user directory:
   - Root: `MacAppSupport`
   - Subdirectory: `Godot/app_userdata/Towering Tower/steam_cloud`
   - Pattern: `*`
   - OS: macOS
   - Recursive: disabled
4. Use Steam's Root Overrides if the same saves must move between Windows and macOS. Without an override, separate OS roots are platform-specific.
5. Save and **Publish** the Steamworks configuration.
6. Enable developer-only Cloud testing first if that option is available for the app.

## Test procedure

1. Launch the game through Steam on computer A.
2. Earn currency or buy an upgrade, then exit normally.
3. Confirm Steam finishes synchronization and shows no conflict.
4. On computer B, launch with the same Steam account and verify progression before making another purchase.
5. Change progression on B, exit, and verify it returns to A.
6. Confirm `settings.cfg` remains local to each computer.

Steam Auto-Cloud performs synchronization before launch and after exit; it does not require Remote Storage API calls in the game.
