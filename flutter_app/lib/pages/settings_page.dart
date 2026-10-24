import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../store.dart';
import '../theme.dart';
import '../update_service.dart';

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

  // ---- 关于 / 检查更新 ----
  String? appVersion;
  bool checkingUpdate = false;
  bool checkedOnce = false;
  ReleaseInfo? newRelease;
  String? updateError;

  @override
  void initState() {
    super.initState();
    UpdateService.currentVersion().then((v) {
      if (mounted) setState(() => appVersion = v);
    });
  }

  Future<void> _checkUpdate() async {
    setState(() {
      checkingUpdate = true;
      updateError = null;
      newRelease = null;
    });
    try {
      final r = await UpdateService.check(force: true);
      if (!mounted) return;
      setState(() {
        newRelease = r;
        checkedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        updateError = e.toString();
        checkedOnce = true;
      });
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  Future<void> _openRelease(ReleaseInfo r) async {
    final uri = Uri.tryParse(r.url);
    if (uri == null) return;
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        setState(() => updateError = '打不开浏览器，请手动访问 ${r.url}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => updateError = '打不开浏览器，请手动访问 ${r.url}');
      }
    }
  }

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
      message = '正在保存并测试连接…';
      ok = true;
    });

    await ConfigStore.save(cfg);

    final probe = ApiClient(
      baseUrl: cfg.baseUrl,
      key: cfg.key,
      cookieName: cfg.cookieName,
    );
    String? fail;
    try {
      await probe.getJson(
        '/api/usage?period=today',
        timeout: const Duration(seconds: 12),
      );
    } on ApiException catch (e) {
      fail = e.toString();
    } on SocketException {
      fail = '无法连接服务器，请检查地址与网络';
    } on TimeoutException {
      fail = '连接超时，请检查网络';
    } catch (e) {
      fail = '连接失败：$e';
    } finally {
      probe.close();
    }
    if (!mounted) return;

    if (fail != null) {
      final err = fail!;
      setState(() {
        saving = false;
        ok = false;
        message = err;
      });
      return;
    }

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
            decoration: const InputDecoration(hintText: 'https://你的网关地址'),
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
          const SizedBox(height: 32),
          Divider(color: AppColors.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Magpie Flutter ${appVersion ?? '…'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '只读监控 · 路由页实时刷新',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF6E778F),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: checkingUpdate ? null : _checkUpdate,
                child: Text(checkingUpdate ? '检查中…' : '检查更新'),
              ),
            ],
          ),
          if (updateError != null) ...[
            const SizedBox(height: 6),
            Text(
              updateError!,
              style: const TextStyle(fontSize: 11.5, color: AppColors.error),
            ),
          ],
          if (newRelease != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.seed.withValues(alpha: 0.45),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${newRelease!.version} 可用',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '在浏览器里下载新版 APK，覆盖安装即可',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () => _openRelease(newRelease!),
                    child: const Text('去下载'),
                  ),
                ],
              ),
            ),
          ],
          if (checkedOnce && newRelease == null && updateError == null) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: AppColors.success,
                ),
                SizedBox(width: 5),
                Text(
                  '已是最新版本',
                  style: TextStyle(fontSize: 11.5, color: AppColors.success),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
