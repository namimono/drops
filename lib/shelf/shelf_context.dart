import 'package:shakepin/shelf/shelf_lifecycle.dart';

/// Per-engine shelf identity, set during [shelfMain] bootstrap.
class ShelfContext {
  ShelfContext._();
  static final ShelfContext instance = ShelfContext._();

  String shelfId = 'unknown';
  ShelfOpenSource source = ShelfOpenSource.hotkey;
  bool isShelfEngine = false;

  void configure({required String id, required ShelfOpenSource openSource}) {
    shelfId = id;
    source = openSource;
    isShelfEngine = true;
  }
}

ShelfOpenSource shelfOpenSourceFromString(String value) {
  return switch (value) {
    'menu' => ShelfOpenSource.menu,
    'shake' => ShelfOpenSource.shake,
    _ => ShelfOpenSource.hotkey,
  };
}
