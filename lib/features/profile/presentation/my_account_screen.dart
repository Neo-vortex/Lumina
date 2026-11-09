import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/display.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../../../core/telegram/widgets/chat_avatar.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/glow_sheet.dart';
import '../data/user_profile_repository.dart';
import 'profile_photo_viewer.dart';

/// Your own account: profile photos (add from gallery or camera, view full
/// screen, make one the main photo, delete), name, @username (checked as you
/// type), bio, phone and user id. Follows TDLib's updates, so changes made on
/// another device show up here too.
class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key, required this.userId, this.pickImage});

  final int userId;

  /// Picks a photo (tests swap it); returns a local path or null.
  final Future<String?> Function(ImageSource source)? pickImage;

  static Route<void> route(int userId) =>
      MaterialPageRoute<void>(builder: (_) => MyAccountScreen(userId: userId));

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  late final _repo = context.read<UserProfileRepository>();
  late final _cache = context.read<TelegramCache>();
  StreamSubscription<CacheEvent>? _events;
  td.UserFullInfo? _full;
  List<td.ChatPhoto> _photos = const [];
  var _busy = false;

  td.User? get _me => _cache.users[widget.userId];

  @override
  void initState() {
    super.initState();
    _events = _cache.events.listen((e) {
      if (e is UserChanged && e.userId == widget.userId) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final full = await _repo.fullInfo(widget.userId);
      if (mounted) setState(() => _full = full);
    } catch (_) {}
    try {
      final photos = await _repo.photos(widget.userId);
      if (mounted) setState(() => _photos = photos);
    } catch (_) {}
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Runs [action] with a progress bar, reports TDLib errors, then reloads.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) _snack(done);
    } on td.TdError catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  // ---- photos ----------------------------------------------------------------

  Future<void> _addPhoto() async {
    final source = await showGlowSheet<ImageSource>(
      context,
      title: 'New profile photo',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: GlowColors.cyan),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: GlowColors.violet),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (source == null || !mounted) return;
    final pick =
        widget.pickImage ??
        (s) async => (await ImagePicker().pickImage(
          source: s,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 92,
        ))?.path;
    final path = await pick(source);
    if (path == null || !mounted) return;
    await _run(() => _repo.setProfilePhoto(path), done: 'Profile photo updated');
  }

  Future<void> _photoActions(td.ChatPhoto photo, int index) async {
    final isMain = index == 0;
    final action = await showGlowSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.fullscreen_rounded),
            title: const Text('View'),
            onTap: () => Navigator.pop(context, 'view'),
          ),
          if (!isMain)
            ListTile(
              leading: const Icon(Icons.star_rounded, color: GlowColors.cyan),
              title: const Text('Set as main photo'),
              onTap: () => Navigator.pop(context, 'main'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_rounded, color: GlowColors.coral),
            title: const Text('Delete', style: TextStyle(color: GlowColors.coral)),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        await Navigator.of(context).push(ProfilePhotoViewer.route(_photos, index));
      case 'main':
        await _run(() => _repo.setMainPhoto(photo.id), done: 'Main photo changed');
      case 'delete':
        final ok = await showGlowConfirm(
          context,
          title: 'Delete this photo?',
          message: 'It is removed from your profile for everyone.',
          confirmLabel: 'Delete',
          icon: Icons.delete_rounded,
          destructive: true,
        );
        if (ok) await _run(() => _repo.deleteProfilePhoto(photo.id), done: 'Photo deleted');
    }
  }

  // ---- text fields -----------------------------------------------------------

  Future<void> _editName(td.User me) async {
    final first = TextEditingController(text: me.firstName);
    final last = TextEditingController(text: me.lastName);
    final save = await showGlowSheet<bool>(
      context,
      title: 'Your name',
      builder: (context) => _SheetForm(
        children: [
          TextField(
            controller: first,
            autofocus: true,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'First name (required)'),
          ),
          TextField(
            controller: last,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'Last name'),
          ),
        ],
      ),
    );
    final f = first.text.trim(), l = last.text.trim();
    first.dispose();
    last.dispose();
    if (save != true) return;
    if (f.isEmpty) return _snack('First name can\'t be empty');
    await _run(() => _repo.setName(f, l));
  }

  Future<void> _editBio() async {
    final bio = TextEditingController(text: _full?.bio?.text ?? '');
    final save = await showGlowSheet<bool>(
      context,
      title: 'Bio',
      builder: (context) => _SheetForm(
        hint: 'A few words about yourself. Anyone who opens your profile sees it.',
        children: [
          TextField(
            controller: bio,
            autofocus: true,
            maxLength: _bioLimit,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
        ],
      ),
    );
    final text = bio.text.trim();
    bio.dispose();
    if (save == true) await _run(() => _repo.setBio(text));
  }

  /// 70 characters, 140 with Premium (TDLib enforces the real limit).
  int get _bioLimit => (_me?.isPremium ?? false) ? 140 : 70;

  Future<void> _editUsername(td.User me) async {
    final current = me.usernames?.editableUsername ?? '';
    final name = await showGlowSheet<String>(
      context,
      title: 'Username',
      builder: (context) =>
          _UsernameForm(initial: current, check: (u) => _repo.checkUsername(widget.userId, u)),
    );
    if (name == null || name == current) return;
    await _run(
      () => _repo.setUsername(name),
      done: name.isEmpty ? 'Username removed' : 'Username set to @$name',
    );
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _snack('$label copied');
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (me == null) return const Scaffold(body: Center(child: Text('Loading your account…')));
    final username = me.usernames?.editableUsername ?? '';
    final bio = _full?.bio?.text ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('My account'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: _photos.isEmpty
                      ? _addPhoto
                      : () => Navigator.of(context).push(ProfilePhotoViewer.route(_photos, 0)),
                  child: ChatAvatar.user(me, size: 120),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: GlowColors.violet,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'New profile photo',
                      icon: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 20),
                      onPressed: _busy ? null : _addPhoto,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            Display.userName(me),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          if (me.phoneNumber.isNotEmpty)
            Text(
              '+${me.phoneNumber}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlowColors.textMuted),
            ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _Label('PROFILE PHOTOS'),
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  if (i == _photos.length) {
                    return _Tile(
                      onTap: _busy ? null : _addPhoto,
                      child: const Icon(Icons.add_rounded, color: GlowColors.cyan, size: 32),
                    );
                  }
                  final p = _photos[i];
                  final small = p.sizes.isEmpty ? null : p.sizes.first.photo;
                  return _Tile(
                    selected: i == 0,
                    onTap: () => _photoActions(p, i),
                    child: small == null
                        ? const SizedBox.shrink()
                        : TdFileImage(
                            file: small,
                            fit: BoxFit.cover,
                            placeholderBytes: Display.minithumbnail(p.minithumbnail),
                            semanticLabel: i == 0 ? 'Main profile photo' : 'Profile photo ${i + 1}',
                          ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 20),
          const _Label('ACCOUNT'),
          const SizedBox(height: 8),
          Card(
            color: GlowColors.surfaceHigh,
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _Row(
                  icon: Icons.person_rounded,
                  label: 'Name',
                  value: Display.userName(me),
                  onTap: () => _editName(me),
                ),
                _Row(
                  icon: Icons.alternate_email_rounded,
                  label: 'Username',
                  value: username.isEmpty ? 'None — tap to set one' : '@$username',
                  muted: username.isEmpty,
                  onTap: () => _editUsername(me),
                  onLongPress: username.isEmpty ? null : () => _copy('Link', 'https://t.me/$username'),
                ),
                _Row(
                  icon: Icons.info_outline_rounded,
                  label: 'Bio',
                  value: bio.isEmpty ? 'Add a few words about yourself' : bio,
                  muted: bio.isEmpty,
                  onTap: _editBio,
                ),
                if (me.phoneNumber.isNotEmpty)
                  _Row(
                    icon: Icons.phone_rounded,
                    label: 'Phone',
                    value: '+${me.phoneNumber}',
                    onTap: () => _copy('Phone', '+${me.phoneNumber}'),
                  ),
                _Row(
                  icon: Icons.tag_rounded,
                  label: 'User ID',
                  value: '${me.id}',
                  onTap: () => _copy('User ID', '${me.id}'),
                ),
              ],
            ),
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Long-press your username to copy your t.me link.',
              style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: GlowColors.violet, fontSize: 12, fontWeight: FontWeight.w700),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.onTap, this.selected = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 84,
      height: 84,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: GlowColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? GlowColors.cyan : Colors.transparent, width: 2),
      ),
      child: child,
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.onLongPress,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool muted;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: GlowColors.cyan),
    title: Text(value, style: muted ? const TextStyle(color: GlowColors.textMuted) : null),
    subtitle: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded, color: GlowColors.textMuted),
    onTap: onTap,
    onLongPress: onLongPress,
  );
}

class _SheetForm extends StatelessWidget {
  const _SheetForm({required this.children, this.hint});
  final List<Widget> children;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        if (hint != null) Text(hint!, style: const TextStyle(color: GlowColors.textMuted, fontSize: 12)),
        const SizedBox(height: 16),
        GlowButton(label: 'Save', onPressed: () => Navigator.pop(context, true)),
      ],
    ),
  );
}

/// Username field that checks availability as you type (debounced) and only
/// lets you save a name TDLib accepts; an empty name removes the username.
class _UsernameForm extends StatefulWidget {
  const _UsernameForm({required this.initial, required this.check});
  final String initial;
  final Future<String?> Function(String username) check;

  @override
  State<_UsernameForm> createState() => _UsernameFormState();
}

class _UsernameFormState extends State<_UsernameForm> {
  late final _text = TextEditingController(text: widget.initial);
  Timer? _debounce;
  String? _error;
  var _checking = false;
  var _ok = true;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _set(String? error, {required bool ok, required bool checking}) => setState(() {
    _error = error;
    _ok = ok;
    _checking = checking;
  });

  void _changed(String v) {
    _debounce?.cancel();
    final name = v.trim();
    if (name.isEmpty || name == widget.initial) {
      _set(null, ok: true, checking: false);
      return;
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$').hasMatch(name)) {
      _set('5–32 characters: letters, digits and _, starting with a letter', ok: false, checking: false);
      return;
    }
    _set(null, ok: false, checking: true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      String? err;
      try {
        err = await widget.check(name);
      } catch (e) {
        err = '$e';
      }
      if (!mounted || _text.text.trim() != name) return;
      _set(err, ok: err == null, checking: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _text.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 32,
            onChanged: _changed,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              errorText: _error,
              helperText: _checking
                  ? 'Checking…'
                  : name.isEmpty
                  ? 'Empty removes your username'
                  : _ok && name != widget.initial
                  ? '@$name is available'
                  : null,
            ),
          ),
          const Text(
            'People can find you by this name and reach you at t.me/username without your phone number.',
            style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          GlowButton(label: 'Save', onPressed: _ok && !_checking ? () => Navigator.pop(context, name) : null),
        ],
      ),
    );
  }
}
