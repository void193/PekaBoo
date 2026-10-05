# Final PekaBoo branding

The source is the user's Desktop file `gamelogofinaltest.png`, preserved unchanged as `pekaboo_logo_source.png`. It replaces the earlier two-character heart logo.

- `pekaboo_logo_cutout.png`: transparent background extraction made with the built-in imagegen tool.
- `pekaboo_logo.png`: the cutout fitted to visible bounds with a small transparent safety margin; used by both menus and the loading screen.
- `menu_logo.gdshader`: a thin cream edge in the desktop menu UI for contrast against the moving world. It does not add a rectangular background or modify the logo asset.

The faces and hands remain opaque; space outside the artwork and inside the wordmark counters is transparent. The black/pink character design and black/blue PekaBoo wordmark are retained. Android adaptive icons keep all lettering in the central mask-safe area. Icons have a deliberate cream backing because launchers mask app icons; the menu logo itself remains transparent.

## Background-extraction prompt

Built-in imagegen was used with `transparent_background: true` and the original Desktop image as the edit target:

> Use case: background-extraction. Edit target: supplied gamelogofinaltest.png, a flat PekaBoo game logo. Remove ONLY its surrounding pale cream background and all blank outer margins to create a clean transparent PNG cutout of the exact supplied artwork. Preserve the EXACT lettering PekaBoo, exact letter shapes, all black/pink/blue colors, character poses and geometry: black-haired boy peeking on the left of the black divider, pink-haired girl with outlined bow on the right, black Peka and bright blue Boo below. Do not redesign, redraw, simplify, embellish, change the typeface or add any text. Preserve the light-colored filled faces and hands as opaque parts of the characters; do not punch holes through their skin. Make background space between the characters, between letters, and the enclosed holes inside the P, a, B, o, o transparent. Preserve the bow's fine light outline. Make the exterior silhouette edges clean, smoothly antialiased, with no cream matte fringe or rectangular backdrop. No drop shadow, no glow, no gradients added. Deliver the entire unchanged logo together with complete text in one high-resolution genuinely transparent PNG, centered with a small transparent safety margin.

Regenerate size variants using `tools/render_boot_splash.gd`; it uses the saved cutout and does not call imagegen again.
