import 'package:flutter_test/flutter_test.dart';
import 'package:shakepin/shelf/shelf_lifecycle.dart';

void main() {
  late ShelfLifecycleStore store;

  setUp(() {
    store = ShelfLifecycleStore(maxShelves: 20);
  });

  test('hotkey create is persistent', () {
    final result = store.createShelf(source: ShelfOpenSource.hotkey);
    expect(result.isSuccess, isTrue);
    expect(result.session!.lifecycle, ShelfLifecycle.persistent);
    expect(result.session!.source, ShelfOpenSource.hotkey);
  });

  test('menu create is persistent', () {
    final result = store.createShelf(source: ShelfOpenSource.menu);
    expect(result.isSuccess, isTrue);
    expect(result.session!.lifecycle, ShelfLifecycle.persistent);
  });

  test('shake create is transient', () {
    store.beginExternalDrag('drag-1');
    final result = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-1',
    );
    expect(result.isSuccess, isTrue);
    expect(result.session!.lifecycle, ShelfLifecycle.transient);
    expect(store.dragSession!.shakeShelfId, result.session!.id);
  });

  test('same drag session rejects second shake create', () {
    store.beginExternalDrag('drag-1');
    expect(
      store
          .createShelf(source: ShelfOpenSource.shake, dragSessionId: 'drag-1')
          .isSuccess,
      isTrue,
    );
    final second = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-1',
    );
    expect(second.isSuccess, isFalse);
    expect(second.rejectedReason, 'shake_shelf_already_exists');
    expect(store.count, 1);
  });

  test('shake drop accepted promotes to persistent', () {
    store.beginExternalDrag('drag-1');
    final created = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-1',
    );
    final id = created.session!.id;
    expect(store.markDropAccepted(id, dragSessionId: 'drag-1'), isTrue);
    expect(store.session(id)!.lifecycle, ShelfLifecycle.persistent);
    expect(store.session(id)!.acceptedDrop, isTrue);
  });

  test('shake without drop closes on drag end', () {
    store.beginExternalDrag('drag-1');
    final created = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-1',
    );
    final id = created.session!.id;
    final toClose = store.endExternalDrag('drag-1');
    expect(toClose, [id]);
    for (final closeId in toClose) {
      store.beginClose(closeId);
      store.markClosed(closeId);
    }
    expect(store.count, 0);
  });

  test('persistent shake shelf survives drag end', () {
    store.beginExternalDrag('drag-1');
    final created = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-1',
    );
    final id = created.session!.id;
    store.markDropAccepted(id, dragSessionId: 'drag-1');
    final toClose = store.endExternalDrag('drag-1');
    expect(toClose, isEmpty);
    expect(store.session(id)!.lifecycle, ShelfLifecycle.persistent);
  });

  test('new drag session can create another shake shelf', () {
    store.beginExternalDrag('drag-1');
    final first = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-1',
    );
    store.markDropAccepted(first.session!.id, dragSessionId: 'drag-1');
    store.endExternalDrag('drag-1');

    store.beginExternalDrag('drag-2');
    final second = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-2',
    );
    expect(second.isSuccess, isTrue);
    expect(store.count, 2);
  });

  test('20th shelf allowed, 21st rejected', () {
    for (var i = 0; i < 20; i++) {
      expect(
        store.createShelf(source: ShelfOpenSource.hotkey).isSuccess,
        isTrue,
      );
    }
    final overflow = store.createShelf(source: ShelfOpenSource.hotkey);
    expect(overflow.isSuccess, isFalse);
    expect(overflow.rejectedReason, 'max_shelves_reached');
    expect(store.count, 20);
  });

  test('closing/closed shelves ignore late events', () {
    final created = store.createShelf(source: ShelfOpenSource.menu);
    final id = created.session!.id;
    store.beginClose(id);
    expect(store.shouldIgnoreEvent(id), isTrue);
    expect(store.markDropAccepted(id), isFalse);
    store.markClosed(id);
    expect(store.shouldIgnoreEvent(id), isTrue);
    expect(store.session(id), isNull);
  });

  test('user close on transient begins closing', () {
    store.beginExternalDrag('drag-1');
    final created = store.createShelf(
      source: ShelfOpenSource.shake,
      dragSessionId: 'drag-1',
    );
    final id = created.session!.id;
    expect(store.beginClose(id), isTrue);
    expect(store.session(id)!.lifecycle, ShelfLifecycle.closing);
  });
}
