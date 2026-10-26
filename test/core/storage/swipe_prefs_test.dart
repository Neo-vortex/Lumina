import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/gestures/swipe_actions.dart';
import 'package:lumina/core/storage/app_preferences.dart';

void main() {
  test('swipe defaults: messages ← reply, → react ❤️; chats ← archive, → pin', () {
    final p = AppPreferences.inMemory();
    expect(p.messageSwipe(SwipeSide.left), MessageSwipe.reply);
    expect(p.messageSwipe(SwipeSide.right), MessageSwipe.react);
    expect(p.swipeEmoji, '❤️');
    expect(p.chatSwipe(SwipeSide.left), ChatSwipe.archive);
    expect(p.chatSwipe(SwipeSide.right), ChatSwipe.pin);
  });

  test('choices persist per side', () {
    final p = AppPreferences.inMemory()
      ..setMessageSwipe(SwipeSide.right, MessageSwipe.delete)
      ..setChatSwipe(SwipeSide.left, ChatSwipe.mute)
      ..swipeEmoji = '🔥';
    expect(p.messageSwipe(SwipeSide.right), MessageSwipe.delete);
    expect(p.messageSwipe(SwipeSide.left), MessageSwipe.reply);
    expect(p.chatSwipe(SwipeSide.left), ChatSwipe.mute);
    expect(p.swipeEmoji, '🔥');
  });

  test('quick reactions default to five and keep at most five; emoji animate by default', () {
    final p = AppPreferences.inMemory();
    expect(p.quickReactions, ['❤️', '👍', '🔥', '😂', '😮']);
    expect(p.animatedEmoji, isTrue);
    p
      ..quickReactions = ['🎉', '🙏', '👏', '😢', '🤔', '💯']
      ..animatedEmoji = false;
    expect(p.quickReactions, ['🎉', '🙏', '👏', '😢', '🤔']);
    expect(p.animatedEmoji, isFalse);
  });
}
