import "package:flutter/material.dart";

import "../planner.dart";
import "../scanner.dart";

const categoryOrder = ["Fotos", "Vídeos", "Documentos", "Arquivos", "Áudio", "Aplicativos", "Downloads", "Outros"];

IconData iconForCategory(String category) {
  switch (category) {
    case "Fotos":
      return Icons.photo_library_outlined;
    case "Vídeos":
      return Icons.movie_outlined;
    case "Documentos":
      return Icons.description_outlined;
    case "Arquivos":
      return Icons.folder_zip_outlined;
    case "Áudio":
      return Icons.audiotrack_outlined;
    case "Aplicativos":
      return Icons.android_outlined;
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

    return ListView.builder(
      itemCount: 1 + names.fold<int>(0, (sum, name) => sum + 1 + (_open.contains(name) ? groups[name]!.length : 0)),
      itemBuilder: (context, index) {
        if (index == 0) {
          return CheckboxListTile(
            value: allOn,
            onChanged: widget.enabled && widget.files.isNotEmpty ? (value) => _setAll(widget.files, value == true) : null,
            secondary: Icon(Icons.select_all, color: scheme.primary),
            title: const Text("Selecionar tudo", style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text("${widget.files.length} arquivos · ${formatBytes(total)}"),
          );
        }
        var cursor = index - 1;
        for (final name in names) {
          if (cursor == 0) {
            return _categoryTile(context, name, groups[name]!);
          }
          cursor--;
          final files = groups[name]!;
          if (_open.contains(name)) {
            if (cursor < files.length) {
              final file = files[cursor];
              return CheckboxListTile(
                value: widget.selected.contains(file.path),
                onChanged: widget.enabled
                    ? (value) {
                        final next = {...widget.selected};
                        if (value == true) {
                          next.add(file.path);
                        } else {
                          next.remove(file.path);
                        }
                        widget.onChanged(next);
                      }
                    : null,
                secondary: Icon(iconForCategory(file.category), color: scheme.primary),
                title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatBytes(file.bytes)),
              );
            }
            cursor -= files.length;
          }
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _categoryTile(BuildContext context, String name, List<LocalFile> files) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = files.fold<int>(0, (sum, file) => sum + file.bytes);
    final marked = files.where((file) => widget.selected.contains(file.path)).length;
    final allOn = marked == files.length && files.isNotEmpty;
    final open = _open.contains(name);
    return Column(
      children: [
        ListTile(
          leading: Checkbox(
            value: allOn ? true : (marked == 0 ? false : null),
            tristate: true,
            onChanged: widget.enabled ? (value) => _setAll(files, value == true) : null,
          ),
          title: Row(
            children: [
              Icon(iconForCategory(name), color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))),
            ],
          ),
          subtitle: Text("$marked de ${files.length} · ${formatBytes(bytes)} nesta categoria"),
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
          onTap: () {
            setState(() {
              if (!_open.add(name)) _open.remove(name);
            });
          },
        ),
        const Divider(height: 1),
      ],
    );
  }
}
