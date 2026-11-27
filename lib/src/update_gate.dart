import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'update_card.dart';
import 'update_controller.dart';
import 'update_status.dart';

/// Wrap your app with this — ideally in `MaterialApp.builder`, above the Navigator.
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.controller,
    required this.child,
    this.cardBuilder,
    this.deferForced,
    this.allowOfflineContinue = false,
    this.allowSkipOptional = true,
    this.showOptionalOverlay = true,
    this.onContinueOffline,
  });

  final UpdateController controller;
  final Widget child;
  final UpdateCardBuilder? cardBuilder;
  final ValueListenable<bool>? deferForced;

  /// When true, the forced screen offers a "Continue with offline content" action.
  final bool allowOfflineContinue;

  /// How an optional update is dismissed: permanent "Skip" (true) vs session "Later" (false).
  final bool allowSkipOptional;

  /// Whether an optional update takes over the screen. Turn it off when the
  /// host already has its own surface for one (a banner, a settings row) —
  /// the forced screen is unaffected.
  final bool showOptionalOverlay;

  /// Optional extra side-effect run when the user continues offline.
  final VoidCallback? onContinueOffline;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  bool _optionalDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.refresh());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refresh());
    }
  }

  Widget _buildCard(BuildContext context, UpdateStatus status) {
    final target = widget.controller.downloadUri;
    final data = UpdateCardData(
      status: status,
      manifest: widget.controller.manifest,
      hasDownloadTarget: target != null,
      downloadHost: target != null && target.scheme == 'https'
          ? target.host
          : null,
      onUpdate: () => unawaited(widget.controller.openDownload()),
      onSkip: status == UpdateStatus.optional
          ? () {
              if (widget.allowSkipOptional) {
                unawaited(widget.controller.skipOptional());
              }
              setState(() => _optionalDismissed = true);
            }
          : null,
      skipLabel: widget.allowSkipOptional ? 'Skip this version' : 'Later',
      onContinueOffline:
          (status == UpdateStatus.forced && widget.allowOfflineContinue)
          ? () {
              widget.controller.continueOffline();
              widget.onContinueOffline?.call();
            }
          : null,
    );
    return widget.cardBuilder?.call(context, data) ??
        DefaultUpdateCard(data: data);
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.deferForced == null
        ? widget.controller
        : Listenable.merge([widget.controller, widget.deferForced!]);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final status = widget.controller.status;

        if (status == UpdateStatus.forced &&
            !widget.controller.offlineContinued &&
            !(widget.deferForced?.value ?? false)) {
          return _ForcedBlock(child: _buildCard(context, status));
        }

        return Stack(
          children: [
            widget.child,
            if (status == UpdateStatus.optional &&
                widget.showOptionalOverlay &&
                !_optionalDismissed)
              _OptionalOverlay(
                onScrimTap: () => setState(() => _optionalDismissed = true),
                child: _buildCard(context, status),
              ),
          ],
        );
      },
    );
  }
}

/// Opaque, un-poppable full-screen block shown instead of the app child.
class _ForcedBlock extends StatelessWidget {
  const _ForcedBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(child: child),
      ),
    );
  }
}

/// Dimmed scrim + centered card for an optional update.
class _OptionalOverlay extends StatelessWidget {
  const _OptionalOverlay({required this.child, required this.onScrimTap});

  final Widget child;
  final VoidCallback onScrimTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: onScrimTap,
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
          Material(
            color: Colors.transparent,
            child: SafeArea(child: child),
          ),
        ],
      ),
    );
  }
}
