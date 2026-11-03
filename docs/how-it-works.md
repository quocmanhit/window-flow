# How it works

- `KeyTap` installs a `CGEventTap` at the HID level on its own thread with its own run loop. The callback only looks
  the key up in a shortcut table guarded by a lock and swallows matches; all Accessibility work is sent to the main
  thread, so a slow app can never delay typing. Swallowing ⌘Tab there is enough to keep the macOS app switcher
  closed; if it is not, a setting turns the system ⌘Tab hotkey off and WindowFlow turns it back on at quit and at the
  next launch.
- `WindowCatalog` keeps one `AXObserver` per app and updates its window list from window created, destroyed,
  and focus notifications, so opening the switcher only refreshes titles and minimized state of windows it already
  knows.
  Windows on other Spaces are found once per app by building `AXUIElement`s from remote tokens
  (`_AXUIElementCreateWithRemoteToken`) on a background queue. Each open does one `CGWindowListCopyWindowInfo` call to
  drop closed windows and read frames for grouping, with short Accessibility timeouts so a hung app is skipped.
- The switcher orders windows by most recent focus, then by the window server's front-to-back order. A quick tap
  (released within 120 ms) switches without ever showing the panel.
- Window groups are recomputed on every open by `WindowGrouping`: per display and Space, up to 12 windows that touch
  a display edge are tried in subsets of 2–4, and a subset counts when its windows don't overlap and cover at least
  90% of the visible frame. The group holding the focused window stays expanded.
- Switching to a window uses SkyLight's `_SLPSSetFrontProcessWithOptions` with the window id, which also moves to
  its Space, then posts the event records that make that window key, and finally `AXRaise`. For a group every member
  gets this in turn, oldest first, because `AXRaise` alone can't lift a window of an inactive app above the active
  app. Private symbols are loaded with `dlsym`; when one is missing WindowFlow falls back to activating the app.
- `Layout` computes target frames in global top-left coordinates from the screen's visible frame and the gap.
  `WindowManager` sets size, position and size again, then reads the frame back: apps that refuse a size or apply it
  late are realigned so the window still sits against the intended edge.
- Nothing runs while idle: no timers or polling. The switcher's watchdog timer only exists while the panel is shown.
- The switcher panel is plain AppKit. Its Liquid Glass background is `NSGlassEffectView`, looked up at runtime because
  the build SDK predates it; the private variant 6 with a white wash is what matches the macOS app switcher, and the
  wash strength is the opacity setting. Without Liquid Glass it falls back to `NSVisualEffectView`, clipped by a mask
  image because a layer corner radius does not clip a behind-window blur.
