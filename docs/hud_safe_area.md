# HUD safe area and notifications (v0.03A2)

Owner playtest: messages sat too close to / partly off the left edge.

## HudSafeArea

Every HUD layer (PrototypeHud, RideHud, NotificationPresenter) builds under a
`HudSafeArea` root: the display safe rectangle
(`DisplayServer.get_display_safe_area()` in logical units — cutouts, rounded
corners, gesture bars removed) inset by **24 units**. The touch controls use
the same safe rect (their own 24-unit padding), so the left column — pause,
score, hire card, speed, steering pad — shares one edge. Simulate cutouts with
`-- --simulate-safe-area=L,T,R,B` (logical units) for screenshots.

## Layout (inside the safe root)

| Zone | Content |
|---|---|
| top-left | pause (touch), score to its right; hire card below (y 76, ≤ 400 wide, ≤ 7 lines) |
| top-centre | GPS (y 0), combo (y 64), **banner column** (y 118, between the side cards) |
| top-right | active ride card; the result card takes the same column after the ride |
| centre | skill popups (y 260 → 228) |
| bottom-centre | passenger line, centre column, above the bottom controls |
| bottom-left | speed + km/h above the steering pad (touch) / at the bottom (desktop) |

Every card is width-capped and word-wrapped (`AUTOWRAP_WORD_SMART`, max lines)
so long translations (Sinhala/Tamil later) wrap instead of overflowing.

## NotificationPresenter

One place for banners (categories SKILL / WARNING / INCIDENT / DAMAGE / RIDE,
priorities NORMAL < HIGH < CRITICAL, two slots, ≤ 2 lines each). Critical:
pedestrian impact, tuk disabled / resetting, ride failed. High: passenger on
board, major incident, tuk damaged. While a CRITICAL banner is up, score
popups are suppressed (no stacking over warnings).

## Tests

`hud_safe_area_test.tscn`: 1920×1080, 2400×1080, 2340×1080, 2520×1080,
1280×800 × {full, left cutout, right cutout, both sides, gesture bar,
asymmetric} with long names/places/notices: every element inside the safe
rect + margin, clear of every touch control, no overlaps between cards shown
together, result card clear of banners, left-column alignment (2,793 checks).
