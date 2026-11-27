# Changelog

## 0.1.0

- First release.
- `UpdateController`: turns your API's update manifest into `none`,
  `optional` or `forced`, with integer build floors and dotted versions.
- `UpdateGate`: the optional card (with "Skip this version") and the
  un-poppable forced block; `deferForced`, `showOptionalOverlay` and
  `cardBuilder` to fit your app.
- An offline latch, so a forced update the app has seen can't be escaped by
  going offline.
- `reportServerFloor` for an `X-Min-Build` floor read off any response.
- Allow-listed download hosts (`allowedDownloadHosts`,
  `setMoreDownloadHosts`); no hosts opens no https link.
- Allow-listed store apps (`allowedStoreAppIds`, `allowAnyStoreLink`): a
  `market://` or `itms-apps://` link opens only an app you list; none opens
  no store link.
- `refresh()` joins a refresh already on its way, and keeps the 6-hour
  throttle for a check that applied a manifest: a failed one is retried
  after `minRetryInterval` (1 minute). `refresh(reconnect: true)`, for the
  network coming back, skips that minute once after a failed attempt, never
  after one that applied a manifest. A `clock` for tests.
- Runs on Android, iOS, Linux, macOS, Windows and the web.
