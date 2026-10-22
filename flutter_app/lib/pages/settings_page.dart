import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  final AppConfig initial;
  final bool setupMode;
  final ValueChanged<AppConfig>? onSaved;

  const SettingsPage({
    super.key,
    required this.initial,
    this.setupMode = false,
    this.onSaved,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController base =
      TextEditingController(text: widget.initial.baseUrl);
  late final TextEditingController key = TextEditingController();
  late final TextEditingController cookie =
      TextEditingController(text: widget.initial.cookieName);
  late bool hasKey = widget.initial.hasKey;
  String message = '';
  bool ok = false;
  bool saving = false;

  @override
  void dispose() {
    base.dispose();
    key.dispose();
    cookie.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final baseUrl = base.text.trim();
    final keyText = key.text.trim();
    final cookieName =
        cookie.text.trim().isEmpty ? 'magpie_web_3430' : cookie.text.trim();

    if (!RegExp(r'^https?://').hasMatch(baseUrl)) {
      setState(() {
        message = '地址必须以 http:// 或 https:// 开头';
        ok = false;
      });
      return;
    }
    if (keyText.isEmpty && !hasKey) {
      setState(() {
        message = '请填写访问密钥';
        ok = false;
      });
      return;
    }

    final cfg = AppConfig(
      baseUrl: baseUrl,
      key: keyText.isEmpty ? widget.initial.key : keyText,
      cookieName: cookieName,
    );

    setState(() {
      saving = true;
      message = '正在保存…';
      ok = true;
    });

    await ConfigStore.save(cfg);
    if (!mounted) return;

    if (widget.onSaved != null) {
      widget.onSaved!(cfg);
    } else {
      Navigator.of(context).pop(cfg);
    }
  }

  Future<void> _clearKey() async {
    await ConfigStore.clearKey();
    if (!mounted) return;
    setState(() {
      hasKey = false;
      message = '已清除保存的密钥';
      ok = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.setupMode
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: const Text(
          '设置',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            widget.setupMode ? '连接 Magpie' : '连接设置',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            '密钥只保存在这台手机，不会上传到任何地方。',
            style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          const Text('网关地址', style: TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: base,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://magpie.example.invalid'),
          ),
          const SizedBox(height: 18),
          const Text('访问密钥', style: TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: key,
            obscureText: true,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: hasKey ? '已保存，留空则不修改' : '粘贴 ?k= 后面的密钥',
            ),
          ),
          const SizedBox(height: 18),
          const Text('Cookie 名称', style: TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: cookie,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'magpie_web_3430'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? '保存中…' : '保存并连接'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: saving ? null : _clearKey,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: AppColors.outline, width: 0.8),
              foregroundColor: AppColors.onSurfaceVariant,
            ),
            child: const Text('清除已保存的密钥'),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: ok ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(height: 36),
          const Center(
            child: Column(
              children: [
                Text(
                  'Magpie Flutter v1.0.0',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF6E778F)),
                ),
                SizedBox(height: 2),
                Text(
                  '只读监控 · 路由页实时刷新',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF6E778F)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
