import 'package:flutter/material.dart';

class FolderEditorScreen extends StatelessWidget {
  const FolderEditorScreen({super.key});

  static Route<void> route({int? folderId}) => MaterialPageRoute(builder: (_) => const FolderEditorScreen());

  @override
  Widget build(BuildContext context) => const Scaffold();
}
