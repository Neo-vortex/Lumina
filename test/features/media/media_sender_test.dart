import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/media/ffmpeg_service.dart';
import 'package:lumina/features/media/data/media_sender.dart';

MediaProbe audioProbe({String? title, String? performer}) => MediaProbe(
  path: '/music/song.mp3',
  sizeBytes: 4000000,
  duration: const Duration(seconds: 215),
  width: 0,
  height: 0,
  videoCodec: null,
  audioCodec: 'mp3',
  bitrate: 320000,
  pixelFormat: null,
  frameRate: null,
  rotation: 0,
  title: title,
  performer: performer,
);

void main() {
  test('audio is music only when picked from the Music tile', () {
    expect(kindForPath('/a/song.MP3', music: true), MediaKind.audio);
    expect(kindForPath('/a/song.mp3'), MediaKind.file);
    expect(kindForPath('/a/notes.pdf', music: true), MediaKind.file);
    expect(kindForPath('/a/clip.mp4', music: true), MediaKind.video);
  });

  test('container tags: any case, artist falls back to album artist', () {
    expect(FfmpegService.audioTags(null), (null, null));
    expect(FfmpegService.audioTags({'TITLE': ' Song ', 'ARTIST': 'Band'}), ('Song', 'Band'));
    expect(FfmpegService.audioTags({'title': 'Song', 'album_artist': 'Various', 'artist': ''}), (
      'Song',
      'Various',
    ));
  });

  test('track title: tag first, then the file name without extension', () {
    final tagged = PickedMedia(
      path: '/m/01 track.mp3',
      kind: MediaKind.audio,
      probe: audioProbe(title: 'Real'),
    );
    final untagged = PickedMedia(path: '/m/01 track.mp3', kind: MediaKind.audio, probe: audioProbe());
    expect(trackTitle(tagged), 'Real');
    expect(trackTitle(untagged), '01 track');
  });

  test('music becomes InputMessageAudio, clipped to 64 characters', () async {
    final media = PickedMedia(
      path: '/m/song.mp3',
      kind: MediaKind.audio,
      probe: audioProbe(title: 'x' * 80, performer: 'Band'),
    );
    final content = await MediaSender(FfmpegService()).build(media, caption: null);
    final audio = (content as td.InputMessageAudio).audio;
    expect(audio.title.length, 64);
    expect(audio.performer, 'Band');
    expect(audio.duration, 215);
    expect((audio.audio as td.InputFileLocal).path, '/m/song.mp3');
  });

  test('music sent as a file stays a document', () async {
    final media = PickedMedia(path: '/m/song.mp3', kind: MediaKind.audio, probe: audioProbe());
    final content = await MediaSender(FfmpegService()).build(media, caption: null, asFile: true);
    expect(content, isA<td.InputMessageDocument>());
  });
}
