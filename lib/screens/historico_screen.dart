import 'package:flutter/material.dart';
import 'package:folha_certa/theme/app_theme.dart';

class HistoricoScreen extends StatelessWidget {
  const HistoricoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dias = [
      ('29/09/2026', '08:01', '12:02', '13:00', '18:04', '08:05'),
      ('26/09/2026', '08:12', '12:00', '13:05', '17:58', '07:41'),
      ('25/09/2026', '07:58', '12:01', '13:00', '18:10', '08:13'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: dias.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final d = dias[i];
          return Card(
            child: ListTile(
              title: Text(d.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('E ${d.$2}  •  A ${d.$3}  •  R ${d.$4}  •  S ${d.$5}'),
              trailing: Text(d.$6, style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
            ),
          );
        },
      ),
    );
  }
}
