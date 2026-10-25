import 'package:handy_tdlib_next/api.dart' as td;

/// How a message should be sent (user requests: silent, scheduled,
/// send-when-online).
class SendOptions {
  const SendOptions({this.silent = false, this.scheduleAt, this.whenOnline = false});

  final bool silent;
  final DateTime? scheduleAt;
  final bool whenOnline;

  td.MessageSendOptions toTd() => td.MessageSendOptions(
    disableNotification: silent,
    fromBackground: false,
    protectContent: false,
    updateOrderOfInstalledStickerSets: false,
    schedulingState: whenOnline
        ? const td.MessageSchedulingStateSendWhenOnline()
        : scheduleAt != null
        ? td.MessageSchedulingStateSendAtDate(sendDate: scheduleAt!.millisecondsSinceEpoch ~/ 1000)
        : null,
    effectId: 0,
    sendingId: 0,
    onlyPreview: false,
  );
}
