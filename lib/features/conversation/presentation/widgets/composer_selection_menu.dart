import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';
import 'formatting_controller.dart';

/// The composer's text-selection menu: a floating glass pill with the
/// clipboard actions on top and a scrollable strip of formats below, kept
/// above the keyboard and flipped under the selection when there's no room.
class ComposerSelectionMenu extends StatelessWidget {
  const ComposerSelectionMenu({super.key, required this.state, required this.controller});

  final EditableTextState state;
  final TextEditingController controller;

  static const _clipboard = {
    ContextMenuButtonType.cut: (Icons.content_cut_rounded, 'Cut'),
    ContextMenuButtonType.copy: (Icons.copy_rounded, 'Copy'),
    ContextMenuButtonType.paste: (Icons.content_paste_rounded, 'Paste'),
    ContextMenuButtonType.selectAll: (Icons.select_all_rounded, 'Select all'),
  };

  static const _formats = <(IconData, String, td.TextEntityType)>[
    (Icons.format_bold_rounded, 'Bold', td.TextEntityTypeBold()),
    (Icons.format_italic_rounded, 'Italic', td.TextEntityTypeItalic()),
    (Icons.format_underlined_rounded, 'Underline', td.TextEntityTypeUnderline()),
    (Icons.format_strikethrough_rounded, 'Strikethrough', td.TextEntityTypeStrikethrough()),
    (Icons.blur_on_rounded, 'Spoiler', td.TextEntityTypeSpoiler()),
    (Icons.code_rounded, 'Monospace', td.TextEntityTypeCode()),
    (Icons.data_object_rounded, 'Code block', td.TextEntityTypePre()),
    (Icons.format_quote_rounded, 'Quote', td.TextEntityTypeBlockQuote()),
    (Icons.unfold_less_rounded, 'Collapsible quote', td.TextEntityTypeExpandableBlockQuote()),
  ];

  @override
  Widget build(BuildContext context) {
    final anchors = state.contextMenuAnchors;
    final c = controller;
    final formatting = c is FormattingController && c.hasSelection;
    final clipboard = [
      for (final item in state.contextMenuButtonItems)
        if (_clipboard[item.type] case (final icon, final label))
          _IconAction(icon: icon, label: label, onTap: item.onPressed),
    ];

    final media = MediaQuery.of(context);
    const gap = 8.0;
    return Padding(
      // Never under the keyboard or the status bar.
      padding: EdgeInsets.only(top: media.padding.top + gap, bottom: media.viewInsets.bottom + gap),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchors.primaryAnchor - Offset(0, media.padding.top + gap),
          anchorBelow:
              (anchors.secondaryAnchor ?? anchors.primaryAnchor) - Offset(0, media.padding.top + gap),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: media.size.width - 24),
          child: Material(
            color: GlowColors.surfaceHigh.withValues(alpha: 0.97),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: GlowColors.violet.withValues(alpha: 0.5)),
            ),
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: glow(GlowColors.violet, intensity: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (clipboard.isNotEmpty)
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: clipboard),
                    if (formatting && clipboard.isNotEmpty)
                      Divider(height: 6, thickness: 1, color: GlowColors.outline.withValues(alpha: 0.6)),
                    if (formatting) _FormatStrip(controller: c, hideToolbar: state.hideToolbar),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatStrip extends StatelessWidget {
  const _FormatStrip({required this.controller, required this.hideToolbar});

  final FormattingController controller;
  final VoidCallback hideToolbar;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (icon, label, type) in ComposerSelectionMenu._formats)
            _IconAction(
              icon: icon,
              label: label,
              active: c.isApplied(type),
              onTap: () {
                c.toggle(type);
                hideToolbar();
              },
            ),
          _IconAction(
            icon: Icons.link_rounded,
            label: 'Link',
            onTap: () async {
              hideToolbar();
              await promptFormattingLink(context, c);
            },
          ),
          _IconAction(
            icon: Icons.format_clear_rounded,
            label: 'Clear formatting',
            onTap: () {
              c.clearFormatting();
              hideToolbar();
            },
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: active
            ? BoxDecoration(shape: BoxShape.circle, color: GlowColors.violet.withValues(alpha: 0.22))
            : null,
        child: Icon(icon, size: 22, color: active ? GlowColors.violet : GlowColors.text),
      ),
    ),
  );
}
