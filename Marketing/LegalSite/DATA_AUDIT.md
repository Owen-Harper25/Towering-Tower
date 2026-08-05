# Towering Tower privacy implementation audit

Audit date: August 2, 2026

This is the implementation record supporting the public privacy-policy draft. Re-run the audit whenever networking, analytics, account, cloud-save, crash-reporting, chat, moderation, or website services change.

## Current findings

- Steam integration uses GodotSteam and `SteamMultiplayerPeer`.
- Multiplayer uses public Steam lobbies with a maximum of 20 members.
- Lobby discovery is worldwide and filters for the `ToweringTower` lobby tag.
- The host lobby name is the host's Steam persona name plus `'s Tower`.
- Connections use Steam relay access and peer-hosted multiplayer. No separate Circular Studios game server or HTTP backend was found.
- Player Steam persona names are synchronized to other participants.
- Gameplay state is exchanged through Godot RPCs, including movement, combat, health/revive status, teams, cosmetics, boon choices, enemies, and scene changes.
- Local settings are stored at `user://settings.cfg`.
- Metaprogression, currency, upgrades, and cosmetics are stored at `user://steam_cloud/meta_progression.cfg`, with one-time migration from `user://meta_progression.cfg`.
- The older resource save path is prepared at `user://steam_cloud/CrowManSaveFile.tres`, with one-time migration from `user://CrowManSaveFile.tres` if that system is re-enabled.
- Machine-specific settings remain at `user://settings.cfg` and should not be synchronized through Steam Cloud.
- No analytics SDK, advertising SDK, HTTP request client, voice capture, text-chat storage, developer account system, or automated crash-report upload was found in project scripts.
- Export privacy declarations currently mark crash data and other reviewed platform categories as not collected.

## Code reviewed

- `Scripts/networking.gd`
- `Scripts/main.gd`
- `Scripts/player.gd`
- `Scripts/main_menu.gd`
- `Scripts/meta_progression.gd`
- `Scripts/SaveLoad.gd`
- `Scripts/SaveData.gd`
- `project.godot`
- `export_presets.cfg`

## Portal configuration not visible in this repository

The following must be checked manually in Steamworks before publication:

- Whether Steam Auto-Cloud is enabled and configured to synchronize only the `user://steam_cloud/` directory.
- Steamworks stats and achievements configured only in the partner portal.
- Any Steamworks crash-dump or error-reporting features configured outside the game code.
- Store support contact information and external service links.
- Any website hosting logs or analytics added during deployment.

## Triggers requiring a policy update

Update the public policy before releasing any feature that adds:

- dedicated servers or a Circular Studios backend;
- analytics, telemetry, advertising, attribution, or crash reporting;
- accounts, email collection, newsletters, payments, or cross-platform login;
- voice chat, text chat, user-generated content, moderation, or reports;
- leaderboards or remotely stored progression;
- Steam Cloud synchronization if the current conditional wording is no longer accurate; or
- a website host, forms, cookies, or scripts whose data practices are not covered by the current wording.
