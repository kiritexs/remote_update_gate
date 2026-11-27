/// The three states the gate can be in.
enum UpdateStatus {
  /// Up to date (or a skipped optional update the user already dismissed).
  none,

  /// A newer build exists and is *recommended* — show a dismissible card.
  optional,

  /// The running build is below the *required* floor — hard-block the app.
  forced;

  /// The app should be blocked from use (forced only).
  bool get isBlocking => this == UpdateStatus.forced;

  /// Something should be shown to the user (optional or forced).
  bool get isPrompting => this != UpdateStatus.none;
}
