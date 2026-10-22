import 'package:flutter/material.dart';

import 'pages/details_page.dart';
import 'pages/overview_page.dart';
import 'pages/providers_page.dart';
import 'pages/quotas_page.dart';
import 'pages/routing_page.dart';
import 'pages/settings_page.dart';
import 'store.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await ConfigStore.load();
  runApp(MagpieApp(initialConfig: config));
}

class MagpieApp extends StatefulWidget {
  final AppConfig initialConfig;
  const MagpieApp({super.key, required this.initialConfig});

  @override
  State<MagpieApp> createState() => _MagpieAppState();
}

class _MagpieAppState extends State<MagpieApp> with WidgetsBindingObserver {
  late AppConfig config;
  AppState? state;
  int tab = 0;
  final PageController _pages = PageController();

  @override
  void initState() {
    super.initState();
    config = widget.initialConfig;
    if (config.hasKey) {
      state = AppState(config);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state?.refreshAll();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    state?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final s = state;
    if (s == null) return;
    if (lifecycle == AppLifecycleState.resumed) {
      if (tab == 1) s.startLive();
      s.refreshAll();
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.hidden) {
      s.stopLive();
    }
  }

  void _connect(AppConfig cfg) {
    final old = state;
    setState(() {
      config = cfg;
      state = AppState(cfg);
      tab = 0;
    });
    old?.dispose();
    if (_pages.hasClients) _pages.jumpToPage(0);
    state?.refreshAll();
  }

  Future<void> _openSettings() async {
    final s = state;
    if (s == null) return;
    final cfg = await Navigator.of(context).push<AppConfig>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(initial: s.config),
      ),
    );
    if (cfg != null) {
      s.updateConfig(cfg);
      s.refreshAll(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeBuilder(
      builder: (theme) {
        final ready = config.hasKey && state != null;
        return MaterialApp(
          title: 'Magpie Flutter',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: theme,
          themeMode: ThemeMode.dark,
          home: ready
              ? Builder(builder: (ctx) => _home(ctx))
              : SettingsPage(
                  initial: config,
                  setupMode: true,
                  onSaved: _connect,
                ),
        );
      },
    );
  }

  Widget _home(BuildContext context) {
    final s = state!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.bar_chart_rounded,
                size: 21,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MAGPIE',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.1,
                    height: 1.1,
                  ),
                ),
                Text(
                  '网关监控',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              s.refreshAll(force: true);
              if (tab == 1) s.loadTraceOnce();
            },
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined, size: 21),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PageView(
        controller: _pages,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _KeepAlive(child: OverviewPage(state: s)),
          _KeepAlive(child: RoutingPage(state: s)),
          _KeepAlive(child: QuotasPage(state: s)),
          _KeepAlive(child: ProvidersPage(state: s)),
          _KeepAlive(child: DetailsPage(state: s)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() => tab = i);
          if (_pages.hasClients) _pages.jumpToPage(i);
          if (i == 1) {
            s.startLive();
          } else {
            s.stopLive();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: '概览',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_rounded),
            label: '路由',
          ),
          NavigationDestination(
            icon: Icon(Icons.donut_large_rounded),
            label: '额度',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_rounded),
            label: '供应商',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_rounded),
            label: '明细',
          ),
        ],
      ),
    );
  }
}

/// 让 PageView 里的页面在切走后保留状态，但首次进入前不构建。
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
