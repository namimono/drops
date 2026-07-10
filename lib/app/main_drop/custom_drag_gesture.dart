import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:shakepin/utils/logger.dart';

/// Minimum pointer movement before a press is treated as a drag.
/// Keeps small jitters from stealing clicks meant for selection.
const _dragDistanceThreshold = 10.0;

class CustomDragGesture extends StatefulWidget {
  const CustomDragGesture({
    super.key,
    required this.child,
    required this.onDragStart,
    this.onInternalDragStart,
    this.onInternalDragUpdate,
    this.onInternalDragEnd,
    this.onInternalDragCancel,
    this.shouldStartExternalDrag,
  });

  final Widget child;
  final void Function() onDragStart;
  final VoidCallback? onInternalDragStart;
  final ValueChanged<Offset>? onInternalDragUpdate;
  final ValueChanged<Offset>? onInternalDragEnd;
  final VoidCallback? onInternalDragCancel;

  /// Lets an internal drag hand off to the native drag session once it leaves
  /// the shelf, preserving drag-out behavior for text items.
  final bool Function(Offset globalPosition)? shouldStartExternalDrag;

  @override
  State<CustomDragGesture> createState() => _CustomDragGestureState();
}

class _CustomDragGestureState extends State<CustomDragGesture> {
  var isDragging = false;
  var _isInternalDrag = false;
  Offset? _pointerDownPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pointerDownPosition = event.position;
        isDragging = false;
        _isInternalDrag = false;
      },
      onPointerMove: (event) {
        if (_pointerDownPosition == null) return;
        if (event.kind != PointerDeviceKind.mouse) return;

        if (!isDragging) {
          final distance = (event.position - _pointerDownPosition!).distance;
          if (distance < _dragDistanceThreshold) return;

          isDragging = true;
          logger.log('Mouse drag started (distance: $distance)');
          if (widget.onInternalDragStart != null) {
            _isInternalDrag = true;
            widget.onInternalDragStart!();
          } else {
            widget.onDragStart();
            return;
          }
        }

        if (!_isInternalDrag) return;
        widget.onInternalDragUpdate?.call(event.position);
        if (widget.shouldStartExternalDrag?.call(event.position) ?? false) {
          _isInternalDrag = false;
          widget.onInternalDragCancel?.call();
          widget.onDragStart();
        }
      },
      onPointerUp: (event) {
        logger.log('onPointerUp');
        if (_isInternalDrag) {
          widget.onInternalDragEnd?.call(event.position);
        }
        isDragging = false;
        _isInternalDrag = false;
        _pointerDownPosition = null;
      },
      onPointerCancel: (event) {
        logger.log('onPointerCancel');
        if (_isInternalDrag) {
          widget.onInternalDragCancel?.call();
        }
        isDragging = false;
        _isInternalDrag = false;
        _pointerDownPosition = null;
      },
      child: widget.child,
    );
  }
}
