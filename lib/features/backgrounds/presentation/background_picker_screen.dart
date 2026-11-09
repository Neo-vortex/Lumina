import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/glow_button.dart';
import '../domain/chat_backdrop.dart';
import 'chat_backdrop_view.dart';

/// Picks a chat background: Lumina's glow (default only), Telegram's
/// gallery, your photo or a colour fill, with blur and dim and a live
/// preview. With [chat] it sets that chat's background in Telegram (for
/// you, or for both in private chats); without, the default in Settings.
/// With [forChatList], the chat list's background (aurora, plain, photo,
/// gallery or fill).
class BackgroundPickerScreen extends StatefulWidget {
  const BackgroundPickerScreen({super.key, this.chat, this.forChatList = false});

  final td.Chat? chat;
  final bool forChatList;

  static Route<void> route({td.Chat? chat, bool forChatList = false}) => MaterialPageRoute(
    builder: (_) => BackgroundPickerScreen(chat: chat, forChatList: forChatList),
  );

  static const fills = <List<int>>[
    [0x1B1F3B, 0x0E1220],
    [0x2A1747, 0x120A22],
    [0x0F2E35, 0x081619],
    [0x3A1F2B, 0x170C11],
    [0x1E2A1A, 0x0C110A],
    [0x202020, 0x0A0A0A],
    [0x2B2440, 0x3A1F3D],
    [0x14324A, 0x2A1450],
  ];

  @override
  State<BackgroundPickerScreen> createState() => _BackgroundPickerScreenState();
}

class _BackgroundPickerScreenState extends State<BackgroundPickerScreen> {
  late final _prefs = context.read<AppPreferences>();
  late final Future<List<td.Background>> _gallery = context
      .read<TdClient>()
      .invoke<td.Backgrounds>(const td.GetInstalledBackgrounds(forDarkTheme: true))
      .then((b) => b.backgrounds)
      .catchError((Object _) => <td.Background>[]);

  // The choice: one of these is set. [_special] is 'glow', 'aurora' or 'plain'.
  String? _special;
  td.Background? _remote;
  String? _photo;
  List<int>? _fill;
  late double _blur = _list
      ? _prefs.listBackdropBlur
      : widget.chat == null
      ? _prefs.backdropBlur
      : 0;
  late double _dim = _list
      ? _prefs.listBackdropDim
      : widget.chat == null
      ? _prefs.backdropDim
      : 0.35;
  late bool _drift = _prefs.listAuroraDrift;
  var _forBoth = false;

  bool get _list => widget.forChatList;

  /// The aurora is (or would stay) the chat list's background.
  bool get _auroraShown =>
      _special == 'aurora' ||
      (_special == null &&
          _remote == null &&
          _photo == null &&
          _fill == null &&
          _list &&
          _prefs.listBackdropKind == 'aurora');

  bool get _isChat => widget.chat != null;
  bool get _private => widget.chat?.type is td.ChatTypePrivate;

  void _pick({String? special, td.Background? remote, String? photo, List<int>? fill}) => setState(() {
    _special = special;
    _remote = remote;
    _photo = photo;
    _fill = fill;
  });

  ChatBackdrop get _preview {
    final spec = switch ((_special, _remote, _photo, _fill)) {
      ('glow', _, _, _) => const BackdropGlow(),
      ('aurora', _, _, _) => BackdropAurora(drift: _drift),
      ('plain', _, _, _) => const BackdropPlain(),
      (_, final r?, _, _) when r.document != null => BackdropImage(file: r.document!.document),
      (_, _, final p?, _) => BackdropImage(path: p),
      (_, _, _, final f?) => BackdropFill([for (final c in f) Color(0xFF000000 | c)]),
      _ => switch (_list ? resolveListBackdrop(_prefs).spec : resolveBackdrop(widget.chat, _prefs).spec) {
        BackdropAurora() => BackdropAurora(drift: _drift),
        final other => other,
      },
    };
    if (_list && spec is! BackdropImage) return ChatBackdrop(spec);
    return ChatBackdrop(spec, blur: _blur, dim: _dim);
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null) _pick(photo: x.path);
  }

  Future<void> _apply() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (_list) {
      _prefs
        ..listBackdropBlur = _blur
        ..listBackdropDim = _dim
        ..listAuroraDrift = _drift;
      if (_special == 'aurora' || _special == 'plain') {
        _prefs.listBackdropKind = _special!;
      } else if (_remote?.document != null) {
        _prefs
          ..listBackdropKind = 'telegram'
          ..listBackdropFileId = _remote!.document!.document.id;
      } else if (_photo != null) {
        _prefs
          ..listBackdropKind = 'photo'
          ..listBackdropPath = _photo;
      } else if (_fill != null) {
        _prefs
          ..listBackdropKind = 'fill'
          ..listBackdropColors = _fill!;
      }
      nav.maybePop();
      return;
    }
    if (!_isChat) {
      _prefs
        ..backdropBlur = _blur
        ..backdropDim = _dim;
      if (_special == 'glow') {
        _prefs.backdropKind = 'glow';
      } else if (_remote?.document != null) {
        _prefs
          ..backdropKind = 'telegram'
          ..backdropFileId = _remote!.document!.document.id;
      } else if (_photo != null) {
        _prefs
          ..backdropKind = 'photo'
          ..backdropPath = _photo;
      } else if (_fill != null) {
        _prefs
          ..backdropKind = 'fill'
          ..backdropColors = _fill!;
      }
      nav.maybePop();
      return;
    }
    final fill = _fill;
    final (td.InputBackground? input, td.BackgroundType? type) = switch ((_remote, _photo, fill)) {
      (final r?, _, _) => (
        td.InputBackgroundRemote(backgroundId: r.id),
        r.type is td.BackgroundTypeWallpaper
            ? td.BackgroundTypeWallpaper(isBlurred: _blur > 0, isMoving: false)
            : r.type,
      ),
      (_, final p?, _) => (
        td.InputBackgroundLocal(background: td.InputFileLocal(path: p)),
        td.BackgroundTypeWallpaper(isBlurred: _blur > 0, isMoving: false),
      ),
      (_, _, final f?) => (
        null,
        td.BackgroundTypeFill(
          fill: f.length == 1
              ? td.BackgroundFillSolid(color: f.first)
              : td.BackgroundFillGradient(topColor: f.first, bottomColor: f.last, rotationAngle: 0),
        ),
      ),
      _ => (null, null),
    };
    try {
      await context.read<TdClient>().invoke<td.Ok>(
        td.SetChatBackground(
          chatId: widget.chat!.id,
          background: input,
          type: type,
          darkThemeDimming: (_dim * 100).round(),
          onlyForSelf: !(_forBoth && _private),
        ),
      );
      nav.maybePop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _tile({
    required Key key,
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) => GestureDetector(
    key: key,
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? GlowColors.violet : GlowColors.outline, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _list
            ? 'Chat list background'
            : _isChat
            ? 'Chat background'
            : 'Default chat background',
      ),
    ),
    body: Column(
      children: [
        // Live preview with sample bubbles.
        SizedBox(
          height: 200,
          child: ChatBackdropView(
            backdrop: _preview,
            child: _list
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SampleRow(name: 'Lumina', text: 'How does it look?', color: GlowColors.violet),
                        SizedBox(height: 14),
                        _SampleRow(name: 'Friends', text: 'Lovely ✨', color: GlowColors.teal),
                      ],
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _Sample(text: 'How does it look?', outgoing: false),
                        SizedBox(height: 8),
                        _Sample(text: 'Lovely ✨', outgoing: true),
                      ],
                    ),
                  ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (_list) ...[
                      _tile(
                        key: const ValueKey('aurora'),
                        selected: _special == 'aurora',
                        onTap: () => _pick(special: 'aurora'),
                        child: SizedBox(
                          width: 72,
                          child: AuroraBackground(
                            drift: false,
                            child: const Center(child: Text('Aurora', textAlign: TextAlign.center)),
                          ),
                        ),
                      ),
                      _tile(
                        key: const ValueKey('plain'),
                        selected: _special == 'plain',
                        onTap: () => _pick(special: 'plain'),
                        child: const ColoredBox(
                          color: GlowColors.background,
                          child: SizedBox(width: 72, child: Center(child: Text('Plain'))),
                        ),
                      ),
                    ] else if (!_isChat)
                      _tile(
                        key: const ValueKey('glow'),
                        selected: _special == 'glow',
                        onTap: () => _pick(special: 'glow'),
                        child: const SizedBox(
                          width: 72,
                          child: Center(child: Text('Lumina\nglow', textAlign: TextAlign.center)),
                        ),
                      ),
                    _tile(
                      key: const ValueKey('photo'),
                      selected: _photo != null,
                      onTap: _pickPhoto,
                      child: const SizedBox(width: 72, child: Icon(Icons.add_photo_alternate_rounded)),
                    ),
                    for (var i = 0; i < BackgroundPickerScreen.fills.length; i++)
                      _tile(
                        key: ValueKey('fill-$i'),
                        selected: _fill == BackgroundPickerScreen.fills[i],
                        onTap: () => _pick(fill: BackgroundPickerScreen.fills[i]),
                        child: Container(
                          width: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                for (final c in BackgroundPickerScreen.fills[i]) Color(0xFF000000 | c),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(
                  'TELEGRAM GALLERY',
                  style: TextStyle(color: GlowColors.violet, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              FutureBuilder<List<td.Background>>(
                future: _gallery,
                builder: (context, snap) {
                  final list = (snap.data ?? const <td.Background>[])
                      .where((b) => b.document != null)
                      .toList();
                  if (list.isEmpty) return const SizedBox(height: 8);
                  return GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.6,
                    children: [
                      for (final b in list)
                        _tile(
                          key: ValueKey('gallery-${b.id}'),
                          selected: _remote?.id == b.id,
                          onTap: () => _pick(remote: b),
                          child: TdFileImage(
                            file: b.document!.thumbnail?.file ?? b.document!.document,
                            fit: BoxFit.cover,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              if (_list && _auroraShown)
                SwitchListTile(
                  value: _drift,
                  onChanged: (v) => setState(() => _drift = v),
                  title: const Text('Gentle motion'),
                  subtitle: const Text('The glows drift slowly; off keeps them still'),
                ),
              _Slider(label: 'Blur', value: _blur, max: 20, onChanged: (v) => setState(() => _blur = v)),
              _Slider(label: 'Dim', value: _dim, max: 0.8, onChanged: (v) => setState(() => _dim = v)),
              if (_private)
                SwitchListTile(
                  value: _forBoth,
                  onChanged: (v) => setState(() => _forBoth = v),
                  title: const Text('Set for both of us'),
                  subtitle: const Text('Otherwise only you see it'),
                ),
            ],
          ),
        ),
        // Always in reach, whatever is scrolled.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: GlowButton(label: 'Apply', onPressed: _apply),
          ),
        ),
      ],
    ),
  );
}

class _Slider extends StatelessWidget {
  const _Slider({required this.label, required this.value, required this.max, required this.onChanged});

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 48, child: Text(label)),
      Expanded(
        child: Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
      ),
    ],
  );
}

/// A chat-list row for the preview.
class _SampleRow extends StatelessWidget {
  const _SampleRow({required this.name, required this.text, required this.color});

  final String name;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: color,
        child: Text(
          name[0],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text(text, style: const TextStyle(color: GlowColors.textMuted)),
          ],
        ),
      ),
    ],
  );
}

class _Sample extends StatelessWidget {
  const _Sample({required this.text, required this.outgoing});

  final String text;
  final bool outgoing;

  @override
  Widget build(BuildContext context) => Align(
    alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: outgoing ? GlowColors.outgoing : null,
        color: outgoing ? null : GlowColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: TextStyle(color: outgoing ? GlowColors.onOutgoing : GlowColors.text)),
    ),
  );
}
