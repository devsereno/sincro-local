import 'package:flutter/material.dart';
import 'package:folha_certa/screens/login_screen.dart';
import 'package:folha_certa/theme/app_theme.dart';

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.mint,
            child: Icon(Icons.person, color: AppColors.navy, size: 36),
          ),
          const SizedBox(height: 12),
          Text('Colaborador', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const Text('colaborador@folhacerta.com.br'),
          const SizedBox(height: 24),
          const ListTile(leading: Icon(Icons.badge_outlined), title: Text('Matrícula'), subtitle: Text('FC-1042')),
          const ListTile(leading: Icon(Icons.work_outline), title: Text('Cargo'), subtitle: Text('Analista')),
          const ListTile(leading: Icon(Icons.schedule_outlined), title: Text('Jornada'), subtitle: Text('08:00 às 18:00')),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(LoginScreen.route, (_) => false);
            },
            child: const Text('Sair'),
          ),
        ],
      ),
    );
  }
}
