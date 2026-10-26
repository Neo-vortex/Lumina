import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/voice/presentation/screens/video_note_recorder_screen.dart';

void main() {
  test('round-video camera fixes its frame rate up front so recording keeps the preview exposure', () {
    final c = videoNoteCamera(
      const CameraDescription(name: '1', lensDirection: CameraLensDirection.front, sensorOrientation: 270),
    );
    expect(c.mediaSettings.fps, 24);
    expect(c.mediaSettings.enableAudio, isTrue);
  });
}
