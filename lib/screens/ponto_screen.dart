import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:folha_certa/theme/app_theme.dart';

class PontoScreen extends StatefulWidget {
  const PontoScreen({super.key});

  @override
  State<PontoScreen> createState() => _PontoScreenState();
}

class _PontoScreenState extends State<PontoScreen> {
  late DateTime _now;
  Timer? _timer;
  final List<DateTime> _batidas = [];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _proximaAcao {
    switch (_batidas.length % 4) {
      case 0:
        return 'Entrada';
      case 1:
        return 'Saída almoço';
      case 2:
        return 'Retorno almoço';
      default:
        return 'Saída';
    }
  }

  void _baterPonto() {
    setState(() => _batidas.insert(0, DateTime.now()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ponto registrado: $_proximaAcao')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hora = DateFormat('HH:mm:ss').format(_now);
    final data = DateFormat("dd/MM/yyyy").format(_now);

    return Scaffold(
      appBar: AppBar(title: const Text('Folha Certa')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: AppColors.navy,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(hora, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(data, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Text('Próxima batida: $_proximaAcao', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: _baterPonto,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Bater ponto'),
            ),
          ),
          const SizedBox(height: 24),
          Text('Hoje', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_batidas.isEmpty)
            const Text('Nenhuma batida ainda.')
          else
            ..._batidas.map((b) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle, color: AppColors.green),
                title: Text(DateFormat('HH:mm:ss').format(b)),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(b)),
              );
            }),
        ],
      ),
    );
  }
}
