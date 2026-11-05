PT COPY TO SEND v1.2 beta

Requirements:
- REAPER with ReaScript Lua support
- ReaImGui (via ReaPack)

Installation:
1. Keep PT_Copy_To_Send.lua, PT_Send_Core.lua and PT_FMP_Engine.lua in the same folder.
2. Load PT_Copy_To_Send.lua in Actions > Show action list > ReaScript: Load.
3. Select SOURCE tracks; open the dialog; select existing destination tracks in To.
4. Optionally choose a send tap mode and press OK.

New in v1.2:
- New 'Mode:' dropdown located under 'To:' with five options:
    Keep current (default; each send preserves its own existing tap mode)
    Post-Fader (Post-Pan) [I_SENDMODE=0]
    Pre-Fader (Post-FX) [I_SENDMODE=3]
    Pre-Fader (Pre-FX) [I_SENDMODE=1]
    Pre-Receive (media and monitoring only) [I_SENDMODE=8]
- Mode selection remembered through REAPER session (not saved to project as an UI preference).
- All matching existing sends are modified together on OK, never creates sends.
- Changing tap mode does not require copying Volume/Pan/Mute or enabling FMP.
- Mode changes belong to the same undo transaction as Copy to Send.
- FMP reads effective mode after the requested change.
- Switching an ALREADY FMP-linked Pre-Fader send to Post-Pan neutralizes its
  additional send pan to prevent doubled pan. Unlinked send pans are preserved.
- When a dormant linked Post-Pan send is returned to Pre-Fader, the FMP engine
  restarts and resumes synchronizing it.
- Compact layout extended slightly to 318 x 320 logical interface units.

Important:
- The 'Pre-Receive' mode excludes incoming receives; it only sends track media
  playback and input monitoring (and does not apply to direct hardware outputs).
- This script targets explicit track-to-track sends on selected SOURCE tracks;
  folder/parent routing and hardware outputs are not included.
- FMP v1 remains control rate (20 Hz default), not sample-accurate.
- Stereo Pan and Dual Pan still require further testing.
- The routing UI cannot gain a native new button from ReaScript alone.
- Testing is static/mock-based only: verify in a scratch REAPER project before
  production use.

Update from v1.1:
- Quit REAPER, replace PT_Copy_To_Send.lua. You can retain the same
  PT_Send_Core.lua and PT_FMP_Engine.lua from v1.1.
