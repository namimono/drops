/// Pure shelf lifecycle state machine for multi-window collection shelves.
///
/// Native [ShelfManager] is the authority at runtime; this Dart model mirrors
/// the same rules for unit tests and documentation.
library;

enum ShelfOpenSource { hotkey, menu, shake }

enum ShelfLifecycle {
  creating,
  transient,
  persistent,
  closing,
  closed,
}

enum DragSessionState { idle, dragging, finishing, finished }

class DragSessionModel {
  DragSessionModel({
    required this.id,
    this.state = DragSessionState.dragging,
    this.shakeShelfId,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final String id;
  DragSessionState state;
  String? shakeShelfId;
  final DateTime startedAt;
}

class ShelfSessionModel {
  ShelfSessionModel({
    required this.id,
    required this.source,
    required this.lifecycle,
    this.associatedDragSessionId,
    this.acceptedDrop = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final ShelfOpenSource source;
  ShelfLifecycle lifecycle;
  String? associatedDragSessionId;
  bool acceptedDrop;
  final DateTime createdAt;

  bool get isActive =>
      lifecycle != ShelfLifecycle.closing && lifecycle != ShelfLifecycle.closed;
}

class ShelfCreateResult {
  const ShelfCreateResult._({this.session, this.rejectedReason});

  final ShelfSessionModel? session;
  final String? rejectedReason;

  bool get isSuccess => session != null;

  factory ShelfCreateResult.success(ShelfSessionModel session) =>
      ShelfCreateResult._(session: session);

  factory ShelfCreateResult.rejected(String reason) =>
      ShelfCreateResult._(rejectedReason: reason);
}

/// Pure registry + lifecycle rules. No Flutter / window dependencies.
class ShelfLifecycleStore {
  ShelfLifecycleStore({this.maxShelves = 20});

  final int maxShelves;
  final Map<String, ShelfSessionModel> _sessions = {};
  DragSessionModel? _dragSession;
  int _idCounter = 0;

  int get count =>
      _sessions.values.where((s) => s.isActive).length;

  Iterable<ShelfSessionModel> get sessions => _sessions.values;

  ShelfSessionModel? session(String id) => _sessions[id];

  DragSessionModel? get dragSession => _dragSession;

  String _nextId() {
    _idCounter += 1;
    return 'shelf-$_idCounter';
  }

  ShelfCreateResult createShelf({
    required ShelfOpenSource source,
    String? dragSessionId,
  }) {
    if (count >= maxShelves) {
      return ShelfCreateResult.rejected('max_shelves_reached');
    }

    if (source == ShelfOpenSource.shake) {
      final drag = _dragSession;
      if (drag == null || drag.id != dragSessionId) {
        return ShelfCreateResult.rejected('no_active_drag_session');
      }
      if (drag.shakeShelfId != null) {
        return ShelfCreateResult.rejected('shake_shelf_already_exists');
      }
      if (drag.state != DragSessionState.dragging) {
        return ShelfCreateResult.rejected('drag_session_not_active');
      }
    }

    final id = _nextId();
    final lifecycle = source == ShelfOpenSource.shake
        ? ShelfLifecycle.transient
        : ShelfLifecycle.persistent;

    final session = ShelfSessionModel(
      id: id,
      source: source,
      lifecycle: lifecycle,
      associatedDragSessionId:
          source == ShelfOpenSource.shake ? dragSessionId : null,
    );
    _sessions[id] = session;

    if (source == ShelfOpenSource.shake) {
      _dragSession?.shakeShelfId = id;
    }

    return ShelfCreateResult.success(session);
  }

  void beginExternalDrag(String dragSessionId) {
    _dragSession = DragSessionModel(id: dragSessionId);
  }

  /// Marks drop accepted and promotes transient → persistent.
  /// Returns false if the session cannot accept events.
  bool markDropAccepted(String shelfId, {String? dragSessionId}) {
    final session = _sessions[shelfId];
    if (session == null || !session.isActive) return false;
    if (session.lifecycle == ShelfLifecycle.closing ||
        session.lifecycle == ShelfLifecycle.closed) {
      return false;
    }

    session.acceptedDrop = true;
    if (session.lifecycle == ShelfLifecycle.transient) {
      session.lifecycle = ShelfLifecycle.persistent;
      session.associatedDragSessionId = null;
    }

    if (dragSessionId != null &&
        _dragSession?.id == dragSessionId &&
        _dragSession?.shakeShelfId == shelfId) {
      // Keep shakeShelfId for bookkeeping until drag ends, but shelf is
      // already persistent and will not auto-close.
    }
    return true;
  }

  /// Ends the drag session. Returns shelf ids that must be closed.
  List<String> endExternalDrag(String dragSessionId) {
    final drag = _dragSession;
    if (drag == null || drag.id != dragSessionId) return const [];

    drag.state = DragSessionState.finished;
    final toClose = <String>[];

    final shakeId = drag.shakeShelfId;
    if (shakeId != null) {
      final session = _sessions[shakeId];
      if (session != null &&
          session.lifecycle == ShelfLifecycle.transient &&
          !session.acceptedDrop) {
        toClose.add(shakeId);
      }
    }

    _dragSession = null;
    return toClose;
  }

  bool beginClose(String shelfId) {
    final session = _sessions[shelfId];
    if (session == null) return false;
    if (session.lifecycle == ShelfLifecycle.closed) return false;
    if (session.lifecycle == ShelfLifecycle.closing) return true;
    session.lifecycle = ShelfLifecycle.closing;
    return true;
  }

  void markClosed(String shelfId) {
    final session = _sessions[shelfId];
    if (session == null) return;
    session.lifecycle = ShelfLifecycle.closed;
    _sessions.remove(shelfId);
  }

  bool shouldIgnoreEvent(String shelfId) {
    final session = _sessions[shelfId];
    if (session == null) return true;
    return session.lifecycle == ShelfLifecycle.closing ||
        session.lifecycle == ShelfLifecycle.closed;
  }
}
