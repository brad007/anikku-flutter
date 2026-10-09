import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_button.dart';

class InputField {
  const InputField(this.label, {this.initial = '', this.multiline = false});
  final String label;
  final String initial;
  final bool multiline;
}

Future<List<String>?> requestFields(
  BuildContext context, {
  required String title,
  required List<InputField> fields,
  String? description,
  String submit = 'Save',
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _InputDialog(
    title: title,
    fields: fields,
    description: description,
    submit: submit,
  ),
);

class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.fields,
    required this.submit,
    this.description,
  });
  final String title;
  final List<InputField> fields;
  final String submit;
  final String? description;
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final controllers = widget.fields
      .map((e) => TextEditingController(text: e.initial))
      .toList();
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void submit() =>
      Navigator.pop(context, controllers.map((e) => e.text).toList());
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
      const SingleActivator(LogicalKeyboardKey.goBack): () =>
          Navigator.pop(context),
    },
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(widget.description!),
                ),
              for (var i = 0; i < widget.fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextField(
                    controller: controllers[i],
                    autofocus: i == 0,
                    maxLines: widget.fields[i].multiline ? 7 : 1,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: widget.fields[i].label,
                    ),
                    onSubmitted: (_) {
                      if (i == widget.fields.length - 1) {
                        submit();
                      } else {
                        FocusScope.of(context).nextFocus();
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton(
          'Cancel',
          icon: Icons.close,
          onPressed: () => Navigator.pop(context),
        ),
        ActionButton(widget.submit, icon: Icons.check, onPressed: submit),
      ],
    ),
  );
}
