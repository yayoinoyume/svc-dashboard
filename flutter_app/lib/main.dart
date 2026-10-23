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

  /// 当前页签放在 Notifier 里，切页只通知导航栏和 TickerMode，
  /// 不再重建 Scaffold / PageView / 主题。
  final ValueNotifier<int> _tab = ValueNotifier(0);

  late List<Widget> _pageViews = const [];

  @override
  void initState() {
    super.initState();
    config = widget.initialConfig;
    if (config.hasKey) {
      state = AppState(config);
      _pageViews = _pagesFor(state!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state?.refreshAll();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tab.dispose();
    state?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final s = state;
    if (s == null) return;
    if (lifecycle == AppLifecycleState.resumed) {
      if (_tab.value == 1) s.startLive();
      s.refreshAll();
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.hidden) {
      s.stopLive();
    }
  }

  List<Widget> _pagesFor(AppState s) => [
        OverviewPage(state: s),
        RoutingPage(state: s),
        QuotasPage(state: s),
        ProvidersPage(state: s),
        DetailsPage(state: s),
      ];

  void _connect(AppConfig cfg) {
    final old = state;
    setState(() {
      config = cfg;
      state = AppState(cfg);
      _pageViews = _pagesFor(state!);
      _tab.value = 0;
    });
    old?.dispose();
    state?.refreshAll();
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
              ? _HomeShell(
                  key: ObjectKey(state),
                  state: state!,
                  pages: _pageViews,
                  tab: _tab,
                )
              : SettingsPage(
                  initial: config,
                  setupMode: true,
                  onSaved: _connect,
                ),
        );
      },
    );
  }
}

class _HomeShell extends StatefulWidget {
  final AppState state;
  final List<Widget> pages;
  final ValueNotifier<int> tab;

  const _HomeShell({
    super.key,
    required this.state,
    required this.pages,
    required this.tab,
  });

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  final PageController _pc = PageController();

  /// PageView 只创建一次，切页时不会重建。
  late final Widget _body = PageView(
    controller: _pc,
    physics: const NeverScrollableScrollPhysics(),
    children: [
      for (var i = 0; i < widget.pages.length; i++)
        ValueListenableBuilder<int>(
          valueListenable: widget.tab,
          builder: (_, tab, __) => TickerMode(
            // 离屏页面静音 Ticker，避免流向图等循环动画后台重绘。
            enabled: tab == i,
            child: _KeepAlive(child: widget.pages[i]),
          ),
        ),
    ],
  );

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (widget.tab.value == i) return;
    widget.tab.value = i;
    if (_pc.hasClients) {
      _pc.animateToPage(
        i,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (i == 1) {
      widget.state.startLive();
    } else {
      widget.state.stopLive();
    }
    // 隐私子页的轮询只在「明细」页开着，切走就停
    if (i != 4) widget.state.stopMaskingLive();
  }

  Future<void> _openSettings() async {
    final cfg = await Navigator.of(context).push<AppConfig>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(initial: widget.state.config),
      ),
    );
    if (cfg != null) {
      widget.state.updateConfig(cfg);
      widget.state.refreshAll(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              widget.state.refreshAll(force: true);
              if (widget.tab.value == 1) widget.state.loadTraceOnce();
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
      body: _body,
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: widget.tab,
        builder: (_, tab, __) => NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: _go,
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
