part of 'cinema_catalog_screen.dart';

class _RowHeader extends StatelessWidget {
  const _RowHeader({
    required this.title,
    required this.horizontalPad,
    this.trailing,
  });

  final String title;
  final double horizontalPad;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: tokens.text,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PosterStrip extends StatelessWidget {
  const _PosterStrip({
    required this.horizontalPad,
    required this.items,
  });

  final double horizontalPad;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return HermesHorizontalShelf(
      height: 318,
      horizontalPadding: horizontalPad,
      itemCount: items.length,
      itemBuilder: (_, idx) => items[idx],
    );
  }
}

class _ResponsivePosterGrid extends StatelessWidget {
  const _ResponsivePosterGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 28,
      children: children,
    );
  }
}

class _CustomListEditorDialog extends StatefulWidget {
  const _CustomListEditorDialog({this.existing});

  final CustomListModel? existing;

  @override
  State<_CustomListEditorDialog> createState() =>
      _CustomListEditorDialogState();
}

class _CustomListEditorDialogState extends State<_CustomListEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _descController =
        TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: tokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        isEdit ? 'Rename list' : 'Create list',
        style: TextStyle(fontWeight: FontWeight.w800, color: tokens.text),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'List name',
                hintText: 'Weekend Sci-Fi',
                filled: true,
                fillColor: tokens.surface3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                filled: true,
                fillColor: tokens.surface3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: tokens.text2)),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((
              name: name,
              description: _descController.text.trim(),
            ));
          },
          child: Text(isEdit ? 'Save' : 'Create list'),
        ),
      ],
    );
  }
}
