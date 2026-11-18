import 'package:flutter/material.dart';

/// محرر نصي بسيط لملف واحد. يرجع النص الجديد عند الحفظ، أو null عند التراجع.
class FileEditorScreen extends StatefulWidget {
  const FileEditorScreen({super.key, required this.path, required this.initialText});

  final String path;
  final String initialText;

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late final TextEditingController _controller;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(() {
      final changed = _controller.text != widget.initialText;
      if (changed != _changed) setState(() => _changed = changed);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تجاهل التعديلات؟'),
        content: const Text('لديك تعديلات غير محفوظة.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('متابعة التحرير')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('تجاهل')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.path, style: const TextStyle(fontSize: 14), textDirection: TextDirection.ltr),
          actions: [
            IconButton(
              tooltip: 'حفظ',
              icon: const Icon(Icons.save_outlined),
              onPressed: _changed ? () => Navigator.of(context).pop(_controller.text) : null,
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _controller,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ),
      ),
    );
  }
}
