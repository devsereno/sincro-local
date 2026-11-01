import "package:flutter/material.dart";

import "../planner.dart";
import "../scanner.dart";

const categoryOrder = ["Fotos", "Vídeos", "Documentos", "Downloads", "Outros"];

IconData iconForCategory(String category) {
  switch (category) {
    case "Fotos":
      return Icons.photo_library_outlined;
    case "Vídeos":
      return Icons.movie_outlined;
    case "Documentos":
      return Icons.description_outlined;
    case "Downloads":
      return Icons.download_outlined;
    default:
      return Icons.folder_outlined;
  }
}

class GroupedFileList extends StatefulWidget {
  const GroupedFileList({
    super.key,
    required this.files,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<LocalFile> files;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  State<GroupedFileList> createState() => _GroupedFileListState();
}

class _GroupedFileListState extends State<GroupedFileList> {
  final _open = <String>{};

  Map<String, List<LocalFile>> get _groups {
    final groups = <String, List<LocalFile>>{};
    for (final file in widget.files) {
      groups.putIfAbsent(file.category, () => []).add(file);
    }
    return groups;
  }

  void _setAll(Iterable<LocalFile> files, bool on) {
    final next = {...widget.selected};
    for (final file in files) {
      if (on) {
        next.add(file.path);
      } else {
        next.remove(file.path);
      }
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _groups;
    final names = [
      for (final name in categoryOrder)
        if (groups.containsKey(name)) name,
      for (final name in groups.keys)
        if (!categoryOrder.contains(name)) name,
    ];
    final allOn = widget.files.isNotEmpty && widget.files.every((file) => widget.selected.contains(file.path));
    final total = widget.files.fold<int>(0, (sum, file) => sum + file.bytes);
    final chosen = widget.files.where((file) => widget.selected.contains(file.path));
    final chosenBytes = chosen.fold<int>(0, (sum, file) => sum + file.bytes);

    return ListView(
      children: [
        CheckboxListTile(
          value: allOn,
          onChanged: widget.enabled && widget.files.isNotEmpty ? (value) => _setAll(widget.files, value == true) : null,
          secondary: Icon(Icons.select_all, color: scheme.primary),
          title: const Text("Selecionar tudo", style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text("${widget.files.length} arquivo(s) · ${formatBytes(total)} · marcados ${formatBytes(chosenBytes)}"),
        ),
        for (final name in names)
          _CategoryBlock(
            name: name,
            files: groups[name]!,
            selected: widget.selected,
            open: _open.contains(name),
            enabled: widget.enabled,
            onToggleOpen: () {
              setState(() {
                if (!_open.add(name)) _open.remove(name);
              });
            },
            onToggleAll: (on) => _setAll(groups[name]!, on),
            onToggleOne: (path, on) {
              final next = {...widget.selected};
              if (on) {
                next.add(path);
              } else {
                next.remove(path);
              }
              widget.onChanged(next);
            },
          ),
      ],
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.name,
    required this.files,
    required this.selected,
    required this.open,
    required this.enabled,
    required this.onToggleOpen,
    required this.onToggleAll,
    required this.onToggleOne,
  });

  final String name;
  final List<LocalFile> files;
  final Set<String> selected;
  final bool open;
  final bool enabled;
  final VoidCallback onToggleOpen;
  final ValueChanged<bool> onToggleAll;
  final void Function(String path, bool on) onToggleOne;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = files.fold<int>(0, (sum, file) => sum + file.bytes);
    final marked = files.where((file) => selected.contains(file.path)).length;
    final allOn = marked == files.length;
    return Column(
      children: [
        ListTile(
          leading: Checkbox(
            value: allOn ? true : (marked == 0 ? false : null),
            tristate: true,
            onChanged: enabled ? (value) => onToggleAll(value == true) : null,
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text("$marked de ${files.length} · ${formatBytes(bytes)}"),
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
          onTap: onToggleOpen,
          iconColor: scheme.primary,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              Icon(iconForCategory(name), color: scheme.primary),
              const SizedBox(width: 8),
              Text(open ? "Toque de novo para encolher" : "Toque para ver os arquivos", style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
        if (open)
          for (final file in files)
            CheckboxListTile(
              value: selected.contains(file.path),
              onChanged: enabled ? (value) => onToggleOne(file.path, value == true) : null,
              secondary: Icon(iconForCategory(file.category), color: scheme.primary),
              title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatBytes(file.bytes)),
            ),
        const Divider(height: 1),
      ],
    );
  }
}
