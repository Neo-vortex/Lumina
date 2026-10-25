import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../theme/glow_colors.dart';
import '../display.dart';
import 'td_file_image.dart';

/// Round avatar: chat/user photo when available, otherwise initials on the
/// id's accent. [glowIntensity] > 0 adds the accent glow (unread, active).
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.id,
    required this.title,
    this.photo,
    this.size = 48,
    this.glowIntensity = 0,
    this.online = false,
  });

  ChatAvatar.chat(td.Chat chat, {Key? key, double size = 48, double glowIntensity = 0, bool online = false})
    : this(
        key: key,
        id: chat.id,
        title: chat.title,
        photo: chat.photo,
        size: size,
        glowIntensity: glowIntensity,
        online: online,
      );

  ChatAvatar.user(td.User? user, {Key? key, double size = 40})
    : this(
        key: key,
        id: user?.id ?? 0,
        title: Display.userName(user),
        photo: user?.profilePhoto == null
            ? null
            : td.ChatPhotoInfo(
                small: user!.profilePhoto!.small,
                big: user.profilePhoto!.big,
                minithumbnail: user.profilePhoto!.minithumbnail,
                hasAnimation: user.profilePhoto!.hasAnimation,
                isPersonal: user.profilePhoto!.isPersonal,
              ),
        size: size,
      );

  final int id;
  final String title;
  final td.ChatPhotoInfo? photo;
  final double size;
  final double glowIntensity;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final accent = Display.accentFor(id);
    final photo = this.photo;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.55)]),
                boxShadow: glowIntensity > 0 ? glow(accent, intensity: glowIntensity) : null,
              ),
              child: ClipOval(
                child: photo != null
                    ? TdFileImage(
                        file: photo.small,
                        placeholderBytes: Display.minithumbnail(photo.minithumbnail),
                      )
                    : Center(
                        child: Text(
                          Display.initials(title),
                          style: TextStyle(
                            color: GlowColors.onAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: size * 0.36,
                          ),
                        ),
                      ),
              ),
            ),
            if (online)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: size * 0.28,
                  height: size * 0.28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: GlowColors.cyan,
                    border: Border.all(color: GlowColors.background, width: 2),
                    boxShadow: glow(GlowColors.cyan, intensity: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
