import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_picker_layout.dart';

void main() {
  const screen = Size(400, 800);
  FolderPickerLayout layout(int n, {double scroll = 0}) =>
      FolderPickerLayout(screen: screen, padding: EdgeInsets.zero, count: n, rightEdge: true, scroll: scroll);

  test('the list goes on the thumb side', () {
    expect(FolderPickerLayout.rightEdgeFor(300, 400), isTrue);
    expect(FolderPickerLayout.rightEdgeFor(100, 400), isFalse);
  });

  test('a short list is centred and the slot under the finger is picked', () {
    final l = layout(4); // 224 tall, top = (800 - 224) / 2 = 288
    expect(l.top, 288);
    expect(l.indexAt(290), 0);
    expect(l.indexAt(288 + 56 * 2 + 1), 2);
    expect(l.indexAt(0), 0, reason: 'clamped');
    expect(l.indexAt(800), 3, reason: 'clamped');
    expect(l.maxScroll, 0);
  });

  test('pulling far from the list cancels', () {
    final l = layout(4);
    expect(l.isCancel(Offset(l.listX - 100, 300)), isFalse);
    expect(l.isCancel(Offset(l.listX - 0.41 * 400, 300)), isTrue);
  });

  test('focus is strongest at the finger and falls off with distance', () {
    final l = layout(6);
    final finger = Offset(l.listX, l.centerOf(2));
    expect(l.focus(2, finger), closeTo(1, 0.01));
    expect(l.focus(3, finger), lessThan(l.focus(2, finger)));
    expect(l.focus(5, finger), lessThan(l.focus(3, finger)));
    final farSideways = Offset(l.listX - 0.3 * 400, l.centerOf(2));
    expect(l.focus(2, farSideways), lessThan(l.focus(2, finger)));
  });

  test('a long list scrolls near the edges and the slot maths follows', () {
    final l = layout(20); // 1120 tall on an 800 screen
    expect(l.maxScroll, 320);
    expect(l.top, 0);
    expect(l.scrollVelocity(400), 0);
    expect(l.scrollVelocity(799), greaterThan(0));
    expect(l.scrollVelocity(1), lessThan(0));
    expect(l.scrollVelocity(799), lessThanOrEqualTo(FolderPickerLayout.maxScrollSpeed));
    final end = l.withScroll(9999);
    expect(end.top, -320, reason: 'scroll clamps to maxScroll');
    expect(end.indexAt(799), 19);
    expect(l.withScroll(-50).top, 0);
  });
}
