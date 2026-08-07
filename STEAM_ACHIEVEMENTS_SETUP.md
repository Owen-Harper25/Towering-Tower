# Towering Tower Steam Achievements

Create these achievements under **Steamworks → App Admin → Stats & Achievements → Achievements**. The **API Name** must match exactly, then publish the Steamworks changes before testing.

| API Name | Display Name | Suggested description |
|---|---|---|
| `ACH_FIRST_DEPLOYMENT` | First Deployment | Enter the alien tree for the first time. |
| `ACH_BRANCH_SEVERED` | The First Cut | Defeat a branch guardian and sever a branch. |
| `ACH_FIVE_BRANCHES` | Conservation Broken | Sever all five major branches. |
| `ACH_CROWN_REACHED` | Touch the Heavens | Reach the Crown Nest. |
| `ACH_WORLD_SAVED` | The Last Nest Is Silent | Defeat the final guardian and save the world. |
| `ACH_TEN_CHARACTERISTICS` | A Soul Well Studied | Recover ten characteristic boons in one expedition. |
| `ACH_ROOTS_TRAINING` | Return to the Roots | Complete a boss cycle in the agency simulation. |
| `ACH_ROOTS_VETERAN` | Simulation Veteran | Survive five simulation bosses in one session. |

The game calls `Steam.setAchievement(API_NAME)` and immediately follows it with `Steam.storeStats()` so Steam can persist the unlock and show its notification. Achievement definitions must exist and be published for those calls to succeed.
