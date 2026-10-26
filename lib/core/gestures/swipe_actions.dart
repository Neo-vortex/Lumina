/// Which way a row was swiped: [left] drags toward the left edge.
enum SwipeSide { left, right }

/// What a swipe on a message does (Settings → Chats → Swipe gestures).
enum MessageSwipe { reply, react, delete, none }

/// What a swipe on a chat-list row does.
enum ChatSwipe { archive, pin, mute, read, delete, none }
