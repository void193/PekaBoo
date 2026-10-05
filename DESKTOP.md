# Desktop development

This checkout lives in `Desktop/PekaBoo-Development`. The downloaded Godot 4.4.1 Windows engine is in `tools/`. Double-click **Launch PekaBoo.cmd** to play. No installation is required.

The desktop menu now has separate Nearby, Online, and Solo pages. The world, models, textures, lighting, gameplay shaders, renderer, and graphics quality settings are unchanged. The Android menu and touch controls are retained. The final supplied PekaBoo logo appears in both menus and boot/loading screens; it already includes the wordmark, so a second game title is not drawn. Its surrounding cream background has been removed. The desktop menu has no opaque logo panel; a fine UI-only outline keeps black lettering readable over the game preview.

Press **F1** for controls. Button tooltips show shortcuts without adding labels to the game HUD. **Tab / Shift+Tab** reaches every visible button and field, **Enter** activates buttons, and arrow keys adjust sliders. Focus stays inside the active dialog. Letters and numbers typed into fields do not trigger gameplay shortcuts.

| Action | Key |
| --- | --- |
| Move / look | WASD or arrows / mouse |
| Jump / crouch | Space / C or Ctrl |
| Run | Hold Shift, or toggle R |
| Main / alternate action | E or F / Q |
| Tools / pranks / emotes | T / P / G |
| Tool slots 1–14 | 1–9, 0, -, =, [, ] |
| Pranks | Shift+1–9, or 1–9 while the Pranks panel is open |
| Emotes | 1–8 while the emote wheel is open |
| Wardrobe / settings | F2 / F3 |
| Close panel / release mouse | Escape |
| Return to main menu | F10 |
| Fullscreen | F11 |
| Nearby host / join | H / J |
| Online host / join | O / I |
| Previous / next character | [ / ] in the menu |
| Practise hide / seek | B / V |
| Explore / chill night | X / N |

Tool, prank, and action shortcuts respect button availability and cooldowns. Open dialogs block movement and gameplay actions. Number keys also select dialog buttons; Tab/Enter covers every remaining button, including dynamically created chill activities and lobby/results actions.

## Verification

From this folder in PowerShell:

```powershell
& .\tools\Godot_v4.4.1-stable_win64_console.exe --headless --path game -- --desktop-qa
& .\tools\Godot_v4.4.1-stable_win64_console.exe --headless --path game -- --qa
& .\tools\Godot_v4.4.1-stable_win64_console.exe --path game -- --desktop-qa
```

The last command saves rendered screenshots to `verification/`. Logs and downloaded executables are excluded from Git. Linux uses the same Godot project and keyboard implementation; run a Godot 4.4 Linux engine with `--path game`. Linux was not available on this Windows machine for an OS-specific launch test.

Verified on this checkout:

- Desktop input suite: **89 passed, 0 failed**, both headless and with the actual renderer.
- Existing gameplay suite: **73 passed, 2 failed**. The two failing checks concern catching hiders in hiding spots and the bot checking hiding spots. Both failures also reproduced using the untouched upstream scripts (baseline log: `verification/baseline-bot-qa.log`).
- Visually inspected the new splash, Nearby/Online/Solo menus, and keyboard help. Screenshots are in `verification/`.
- Logo update: verified the original artwork is preserved byte-for-byte, PNG icon/splash dimensions, all seven Windows ICO sizes, and the rendered Android menu layout. The supplied logo includes the complete wordmark in every size. Android device testing is still outstanding.
- Git whitespace checks passed. All original gameplay assets, import metadata, baked lighting and shaders match the upstream checkout.
- This Windows session exposes a Microsoft virtual display adapter. Godot cannot initialize Vulkan here and automatically uses its Direct3D 12 driver; the full 3D game measured around 2–3 FPS. No renderer or graphics-quality settings were changed to compensate.
- Desktop QA avoids saving the player's settings. No online two-player network session was exercised.

The final original `gamelogofinaltest.png` is preserved in `game/assets/branding/pekaboo_logo_source.png`. The transparent background extraction is in `pekaboo_logo_cutout.png`. `tools/render_boot_splash.gd` trims empty margins from that cutout and creates the fitted menu logo, 192 px launcher icon, 432 px Android adaptive-icon layers, multi-resolution Windows ICO (16–256 px), and 1280×720 boot splash. It retains the complete faces, bow, and wordmark, fits without stretching, and blends transparent edges correctly. Regenerate these assets with:

```powershell
& .\tools\Godot_v4.4.1-stable_win64_console.exe --headless --path game --script ..\tools\render_boot_splash.gd
```

Windows exports now enable icon resource modification. Configure **rcedit** in Godot's editor settings to embed the supplied ICO in an exported EXE; Linux/macOS export hosts also need Wine. See [Godot's Windows icon documentation](https://docs.godotengine.org/en/4.4/tutorials/export/changing_application_icon_for_windows.html). No Windows EXE or Android APK export was tested in this session.
