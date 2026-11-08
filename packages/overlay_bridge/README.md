# overlay_bridge

Carries Android's `microphone` foreground-service type for exactly as long as
the microphone is open, and no longer. Android only.

## Why this exists

The LiveMCQ floating bubble is drawn by `flutter_overlay_window`, whose
`OverlayService` is a foreground service that lives for as long as the bubble
is on screen. That plugin calls `startForeground(id, notification)` without a
type, so the type comes from whatever the app's manifest declares for the
service — and it is fixed there, with no way to turn it on and off.

The app used to declare that service `microphone`. The effect was that showing
a bubble made the app tell Android it was a microphone app, whether or not
anything was listening. Nothing could be done about it from Dart.

So the overlay service is now declared `specialUse`, which is what it actually
is — a window over other apps — and the microphone type lives here, on a
service started around the recording itself and stopped as soon as it ends.

## Use

```dart
await MicForegroundService.instance.acquire(text: 'Listening');
// ... record or dictate ...
await MicForegroundService.instance.release();
```

Calls are reference counted, so dictation and recording can each hold it
without one ending the other's claim. `releaseAll()` drops every claim at once
and is the backstop for a path that acquired and then lost its way out.

Everywhere but Android every call is a no-op, which is also what keeps it quiet
under `flutter test`.

## Notes

- Starting a foreground service from the background is refused on Android 12
  and up unless the app is exempt. Holding `SYSTEM_ALERT_WINDOW`, which the
  bubble needs anyway, is one of the exemptions. A refusal is logged and
  reported, never thrown: recording from the app's own screens does not depend
  on this service.
- `specialUse` needs a justification when a build is submitted to Google Play.
