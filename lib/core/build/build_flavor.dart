import 'package:flutter/services.dart' show appFlavor;

/// Whether this build ships the on-device LLM (SmolLM2, ✨ actions, writing
/// help, reaction suggestions). `--flavor lite` leaves the model and the
/// llama.cpp libraries out; speech (Whisper) stays in both flavors.
/// [appFlavor] is a compile-time constant, so lite builds tree-shake the AI
/// code paths behind this flag.
const bool kOnDeviceLlm = appFlavor != 'lite';
