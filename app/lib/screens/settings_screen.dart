import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../models/study_mode.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StudyMode _studyMode = StudyMode.englishToRussian;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final modeKey = prefs.getString('study_mode') ?? 'english_to_russian';
    setState(() {
      _studyMode = StudyModeExtension.fromStorageKey(modeKey);
      _loading = false;
    });
  }

  Future<void> _saveStudyMode(StudyMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('study_mode', mode.storageKey);
    setState(() {
      _studyMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          if (auth.email != null) ListTile(title: const Text('Email'), subtitle: Text(auth.email!)),
          if (auth.name != null) ListTile(title: const Text('Имя'), subtitle: Text(auth.name!)),
          const Divider(),
          const ListTile(
            title: Text('Режим изучения'),
            subtitle: Text('Выберите направление перевода при изучении карточек'),
          ),
          RadioListTile<StudyMode>(
            title: const Text('Английский → Русский'),
            subtitle: const Text('Показывать английское слово, вводить русский перевод'),
            value: StudyMode.englishToRussian,
            groupValue: _studyMode,
            onChanged: (value) => _saveStudyMode(value!),
          ),
          RadioListTile<StudyMode>(
            title: const Text('Русский → Английский'),
            subtitle: const Text('Показывать русский перевод, вводить английское слово'),
            value: StudyMode.russianToEnglish,
            groupValue: _studyMode,
            onChanged: (value) => _saveStudyMode(value!),
          ),
          RadioListTile<StudyMode>(
            title: const Text('Смешанный'),
            subtitle: const Text('Случайно выбирается направление для каждой карточки'),
            value: StudyMode.mixed,
            groupValue: _studyMode,
            onChanged: (value) => _saveStudyMode(value!),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Выйти'),
            onTap: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
