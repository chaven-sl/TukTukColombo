# Mobile performance (v0.03A)

## SessionPerformanceMonitor

`scripts/performance/session_performance_monitor.gd` — preallocated ring
buffer (36 000 frames ≈ 10 min @ 60 FPS), no per-frame allocation. Summary:

| Field | Meaning |
|---|---|
| `fps_avg`, `fps_p5` | mean FPS; 5th-percentile FPS (from the 95th-percentile frame time) |
| `fps_min_stable_1s` | worst whole second |
| `frame_ms_avg`, `frame_ms_p95` | frame times |
| `traffic_min/max`, `ceiling_min/max`, `budget_changes` | adaptive traffic behaviour |
| `humans_min/max` | active people |
| `draw_calls_avg`, `memory_static_peak_mb` | rendering / memory |
| `renderer`, `resolution`, `device`, `os`, `video_adapter`, `video_api` | context |

`save_summary(tag)` writes `user://perf/<tag>.json` and logs one
`[PerfMonitor]` line (visible in `adb logcat -s godot:V`).

## Device perf test (5 minutes, deterministic)

`DevicePerfTest`: normal world (traffic, pedestrians, crossings, waiting
passengers) with fixed seeds (7), driven by the deterministic
`AutopilotDriver` (moved to `scripts/debug/` so builds can include it).
Human input is disabled during the run.

Start it with: pause screen → *Performance test (5 min)* (debug builds), or
`-- --perf-test[=seconds]`, or the flag file `user://perf_test.flag` that
`tools/android_perf_test.sh` writes with `adb shell run-as`.

## Targets

Mid-range Android: 60 FPS on MEDIUM; low-end floor 30 FPS stable (LOW).
Real-device numbers: see `PROTOTYPE_V003A_REPORT.md` (pending until a
device is connected).
