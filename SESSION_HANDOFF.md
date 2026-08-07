# Towering Tower session handoff

Updated: August 6, 2026

## Current repository state

- Branch: `main`
- HEAD: `ca26aa2` (`Steam Stable`)
- `main` matches `origin/main`.
- AppID is committed as `5051570` in `project.godot`.
- The lobby boon-card debug button removal is committed in `ca26aa2`.
- The legal/privacy site and Steam Cloud save changes are committed and pushed in `c9f2b7f`.

### Uncommitted working-tree state

- Modified: `export_presets.cfg`
  - Adds the Windows `Steam` export preset.
  - External export path: `../Towering-Tower-Builds/Steam/Windows/ToweringTower.exe`
  - File/product version: `0.1.0.0`
  - Company: `Circular Studios`
- Untracked and intended: `Tools/SteamPipe/app_build_5051570.vdf`
- Untracked and intended: `Tools/SteamPipe/depot_build_5051571.vdf`
- Modified: `.gitignore`
  - Prevents accidental root-level Windows exports from being committed.
  - Ignores only tilde-prefixed GodotSteam DLL swap artifacts, not the real extension DLLs.
- Five tracked tilde/TMP GodotSteam scratch copies are intentionally deleted after their hashes matched the real debug DLL. Godot recreates and removes its hot-reload copy as needed; the real debug/release DLLs and `steam_api64.dll` remain intact.
- The three accidental root export files were removed after the newer external Steam build was verified intact.
- `SESSION_HANDOFF.md` is modified by this handoff update.

## Steamworks identifiers and successful first upload

- Game: Towering Tower
- AppID: `5051570`
- Windows content Depot ID: `5051571`
- First uploaded SteamPipe BuildID: `24566582`
- The build was set live for private pre-release testing.
- Steam initially reported `Invalid game configuration` because no valid published launch option was available.
- General Installation was corrected to launch `ToweringTower.exe` on Windows and the Steamworks configuration was published.
- Result: the Steam-installed build launches successfully.

## Local build and SDK locations

- Godot Windows export directory:
  - `C:\Users\Owen\Documents\Towering-Tower-Builds\Steam\Windows`
- Expected build files:
  - `ToweringTower.exe`
  - `steam_api64.dll`
  - `libgodotsteam.windows.template_release.x86_64.dll`
- Steamworks SDK:
  - `C:\steamworks_sdk_165`
- SteamCMD:
  - `C:\steamworks_sdk_165\sdk\tools\ContentBuilder\builder\steamcmd.exe`
- SteamPipe scripts were copied to:
  - `C:\steamworks_sdk_165\sdk\tools\ContentBuilder\scripts\app_build_5051570.vdf`
  - `C:\steamworks_sdk_165\sdk\tools\ContentBuilder\scripts\depot_build_5051571.vdf`
- SteamPipe output/cache:
  - `C:\Users\Owen\Documents\Towering-Tower-Builds\SteamPipeOutput`

## Repeatable upload workflow

1. In Godot, export the `Steam` Windows preset. Ensure the save location remains the external `Towering-Tower-Builds\Steam\Windows` folder and `Export With Debug` is off.
2. Launch SteamCMD from the SDK builder folder.
3. At the `Steam>` prompt run:

   ```text
   login piston_worx
   run_app_build ..\scripts\app_build_5051570.vdf
   quit
   ```

4. Supply the password and Steam Guard code interactively; never save them in VDF files.
5. In Steamworks, open `https://partner.steamgames.com/apps/builds/5051570` and set the new BuildID live on the desired test/default branch.
6. Install/update through the Steam client and test the Steam-installed copy.

## Steamworks and website state

- Public studio identity: Circular Studios.
- Support/privacy email: `circulargamestudios@outlook.com`.
- Static legal site lives in `Marketing/LegalSite/` and has been pushed/deployed through GitHub Pages.
- Privacy and health-warning pages were prepared for Steamworks external-link fields.
- Steam Auto-Cloud settings were discussed, but the portal configuration should still be rechecked during the Steam-installed smoke test.

## Known issues resolved in this session

- Godot `Invalid product version`: fixed by using four-part numeric versions (`0.1.0.0`) for both file and product version.
- Export accidentally written into the repository root: corrected by restoring the external export path.
- SteamCMD/SDK confusion: SteamCMD was located and initialized successfully.
- SteamPipe upload completed successfully.
- Steam `Invalid game configuration`: fixed via the published General Installation launch option.

## Next concrete steps

1. Run a Steam-installed smoke test:
   - overlay opens;
   - hosting/lobby discovery and friend joining work;
   - two-player synchronization works;
   - Steam Cloud persists settings/metaprogression across restart;
   - Nintendo Pro Controller and menu/gameplay controls work;
   - scene transitions and audio buses behave correctly.
2. Decide whether to commit the Windows export preset, `.gitignore` cleanup, temporary-DLL deletions, and `Tools/SteamPipe/*.vdf` scripts. The VDF contains Owen's absolute local paths and may be better parameterized or documented before committing.
3. After multiplayer/Cloud verification, export and upload a fresh test build using the repeatable workflow above.

## Verification performed

- Confirmed the external Windows export contains the executable and both required Steam/GodotSteam DLLs.
- Confirmed SteamCMD initialized and authenticated as `piston_worx`.
- Confirmed SteamPipe uploaded AppID `5051570`, Depot `5051571`, producing BuildID `24566582`.
- User confirmed the game launches successfully from Steam after launch configuration was corrected.
