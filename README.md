# remote_update_gate

Reusable, **API-driven** force / optional update gate for Flutter apps. Redirect
to a download URL — this package never downloads or installs a binary.

## When to use it

Choose it when your **own API** decides which versions may run: sideloaded
builds, private distribution, desktop apps, or any app that needs a kill
switch.

- Two **server-controlled version floors** (dotted versions such as `1.4.0`):
  below the recommended one an update can be skipped, below the required one
  it can't.
- A forced update survives going offline: the last manifest is kept and
  applied at start-up before any network call.
- Update links open only on hosts and store apps you allow, so a tampered
  config can't send people elsewhere.
- Your own card and design, reused across apps through two small interfaces.

If your update prompts should come from the App Store and Google Play
listings instead, [`upgrader`](https://pub.dev/packages/upgrader) is the
established choice.

## The model

Two layers. The client half is here; the server half is the real lock.

| Layer | Where | Job |
|---|---|---|
| **Server version-gate** | your backend | Reject builds below the required floor; the only tamper-proof enforcement |
| **Client gate** | this package | Custom card, offline latch, hard-block forced UI |

The client **fails open**: a missing/zero config gates nobody. The server is the
fail-closed backstop.

## Plug in three things

```dart
class MyStore implements UpdateGateStore { /* SharedPreferences, etc. */ }
class MySource implements UpdateSource {
  Future<UpdateManifest?> fetch() async => manifestFromMyConfig(await api.config());
}

final controller = UpdateController(
  currentVersion: appVersion,         // package_info_plus
  platform: 'android',                // or ios/macos/windows/linux
  store: MyStore(),
  source: MySource(),
);
await controller.init();              // offline latch — before runApp

// In MaterialApp.builder:
builder: (context, child) => UpdateGate(controller: controller, child: child!),
```

## Transport wiring (the every-request signal)

Send the version on every request and read the floor off every response, so a
critical update arms on *any* API call — not just when you fetch config:

```dart
// request:  X-App-Build: <currentVersion>          e.g. 1.3.2
// response: X-Min-Build: <requiredVersion>   →  controller.reportServerFloor(floor)
```

## Backend contract

On every response, stamp:

```
X-Min-Build: <required version, e.g. 1.4.0>
```

When the request's `X-App-Build` is below that floor, **also refuse to serve
data** with a structured body your app recognizes, e.g.:

```json
{ "error": "upgrade_required", "min_version": "1.4.0" }
```

That refusal — not the client card — is what actually forces the update. The
card is UX; the server is the lock.

## States

- `none` — up to date (or a skipped optional the user dismissed).
- `optional` — dismissible card; "Skip this version" persists until the server
  raises the recommended floor.
- `forced` — the whole UI is replaced by an un-poppable block. Never skippable.

Pass `UpdateGate.deferForced` (a `ValueListenable<bool>`) to withhold the forced
block briefly — e.g. while an offline video finishes — without clearing the
`forced` status.

`UpdateGate.showOptionalOverlay: false` drops the optional card's modal
altogether, for a host that already surfaces an optional update its own way (a
banner, a settings row). The forced block is unaffected.

`UpdateGate.cardBuilder` replaces the default card with your own, which is how
an app keeps its own design system — and, on a desktop host with a hidden title
bar, how it keeps window buttons on screen: the forced block replaces the whole
app, so whatever draws your window chrome is gone while it is up.

The default card's text is in English only ("Update now", "Update required").
For other languages, draw your own card with `cardBuilder` and take its text
from your app's localizations.

## Restricting update links

`UpdateController(allowedDownloadHosts: {...})` limits which hosts an https
update link may open, subdomains included. A link to any other host is refused,
and the card shows its "repairing" state instead of an "Update now" button, so a
tampered update config can't send users to another site. **No hosts opens no https
link**; pass `allowAnyDownloadHost: true` to open any.

Store links are checked by the app they open, the same way:
`UpdateController(allowedStoreAppIds: {...})` lists the apps a store link may
open, `market://details?id=<package>` by its package name and
`itms-apps://apps.apple.com/app/id<number>` by its number (without `id`). Any
other app is refused, so a tampered config can't send users to a lookalike's
store page. **No ids opens no store link**; pass `allowAnyStoreLink: true` to
open any.

`setMoreDownloadHosts({...})` adds hosts at run time, replacing the ones added
before. Feed it only hosts your app has verified itself (for example from a
list signed with your release key), never straight from the config the link
comes from: a host list that config can change protects nothing.

The default card also shows the destination host under "Update now"
(`UpdateCardData.downloadHost`), so users can see where the button goes.

## Refreshing

`UpdateGate` calls `controller.refresh()` after its first frame and whenever
the app is resumed; call it yourself on other events (the network coming
back, for example). A refresh already on its way is joined, forced or not.
An unforced one is skipped within `minRefreshInterval` (6 hours) of the last
one that applied a manifest, and within `minRetryInterval` (1 minute) of the
last attempt: a check that failed (offline, a server error) comes back a
minute later, not 6 hours later, and a forced gate still waiting for a
download link polls at most once a minute. `refresh(reconnect: true)` (the
network coming back) skips that minute once after a failed attempt, which was
likely made offline; after one that applied a manifest, or a failed early
reconnect, the minute still holds. So a forced gate waiting for a download
link, whose checks succeed, still polls at most once a minute; while checks
fail, each failed one lets one early reconnect through, about twice a
minute at most. Limit how often you pass it. `refresh(force: true)` (a
manual "Check for updates", the 426 kick) is never held off. Pass `clock` to
drive the throttles in tests.

## Platform support

| Android | iOS | Linux | macOS | Windows | Web |
|---|---|---|---|---|---|
| yes | yes | yes | yes | yes | yes |

The package is plain Flutter with no native code of its own; links open
through `url_launcher`, which covers all six. On the web an https link opens
in a new tab; `market://` and `itms-apps://` links only make sense on the
phones whose stores they name, so give each platform its own link in the
manifest.

## Installation

```yaml
dependencies:
  remote_update_gate: ^0.1.0
```

The controller opens update links with `url_launcher` (`launchUrl`, in the
external app), so there is nothing to add to the platform projects.

## License

MPL-2.0, © 2026 Kiritex.
