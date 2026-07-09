import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:shakepin/utils/logger.dart';

/// Minimum pointer movement before a press is treated as a drag.
/// Keeps small jitters from stealing clicks meant for selection.
const _dragDistanceThreshold = 10.0;

class CustomDragGesture extends StatefulWidget {
  const CustomDragGesture(
      {super.key, required this.child, required this.onDragStart});

  final Widget child;
  final void Function() onDragStart;

  @override
  State<CustomDragGesture> createState() => _CustomDragGestureState();
}

class _CustomDragGestureState extends State<CustomDragGesture> {
  var isDragging = false;
  Offset? _pointerDownPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pointerDownPosition = event.position;
        isDragging = false;
      },
      onPointerMove: (event) {
        if (isDragging || _pointerDownPosition == null) return;
        if (event.kind != PointerDeviceKind.mouse) return;

        final distance = (event.position - _pointerDownPosition!).distance;
        if (distance < _dragDistanceThreshold) return;

        isDragging = true;
        logger.log('Mouse drag started (distance: $distance)');
        widget.onDragStart();
      },
      onPointerUp: (event) {
        logger.log('onPointerUp');
        isDragging = false;
        _pointerDownPosition = null;
      },
      onPointerCancel: (event) {
        logger.log('onPointerCancel');
        isDragging = false;
        _pointerDownPosition = null;
      },
      child: widget.child,
    );
  }
}
