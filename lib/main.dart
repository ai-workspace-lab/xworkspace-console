import 'package:flutter/material.dart';

void main() {
  runApp(const XWorkspaceApp());
}

enum ConsolePage { workspace, openclaw, litellm, vault, terminal }

class XWorkspaceApp extends StatelessWidget {
  const XWorkspaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F6FED),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'XWorkspace Console',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFEAE3D8),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(fontSize: 13, height: 1.35),
        ),
      ),
      home: const ConsoleShell(),
    );
  }
}

class ConsoleShell extends StatefulWidget {
  const ConsoleShell({super.key});

  @override
  State<ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends State<ConsoleShell> {
  ConsolePage _page = ConsolePage.workspace;

  static const _titles = <ConsolePage, String>{
    ConsolePage.workspace: 'Workspace',
    ConsolePage.openclaw: 'OpenClaw',
    ConsolePage.litellm: 'LiteLLM',
    ConsolePage.vault: 'Vault',
    ConsolePage.terminal: 'Terminal',
  };

  static const _subtitles = <ConsolePage, String>{
    ConsolePage.workspace: 'Default home view for the workspace control plane.',
    ConsolePage.openclaw:
        'Gateway and bridge status for the workspace edge layer.',
    ConsolePage.litellm:
        'Model router dashboard with latency, throughput, and cost.',
    ConsolePage.vault: 'Secrets, policy, and access posture for the workspace.',
    ConsolePage.terminal:
        'Dedicated shell surface for ttyd or future terminal embedding.',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 980;
        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isCompact ? 0 : 30),
                border: Border.all(color: const Color(0x1A4A3C2A)),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF9F5EE),
                    Color(0xFFF0E9DE),
                    Color(0xFFE3DACE),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A3F2E16),
                    blurRadius: 28,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: isCompact
                  ? _CompactShell(
                      page: _page,
                      onPageSelected: _setPage,
                      title: _titles[_page]!,
                      subtitle: _subtitles[_page]!,
                      body: _buildPage(_page),
                    )
                  : Row(
                      children: [
                        _Sidebar(page: _page, onPageSelected: _setPage),
                        Expanded(
                          child: Column(
                            children: [
                              _TopBar(
                                title: _titles[_page]!,
                                subtitle: _subtitles[_page]!,
                              ),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: _buildPage(
                                    _page,
                                    key: ValueKey(_page),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  void _setPage(ConsolePage page) {
    if (page == _page) return;
    setState(() => _page = page);
  }

  Widget _buildPage(ConsolePage page, {Key? key}) {
    return KeyedSubtree(
      key: key,
      child: switch (page) {
        ConsolePage.workspace => const WorkspacePage(),
        ConsolePage.openclaw => const OpenClawPage(),
        ConsolePage.litellm => const ModelPage(),
        ConsolePage.vault => const VaultPage(),
        ConsolePage.terminal => const TerminalPage(),
      },
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.page,
    required this.onPageSelected,
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final ConsolePage page;
  final ValueChanged<ConsolePage> onPageSelected;
  final String title;
  final String subtitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: _TopBar(title: title, subtitle: subtitle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ConsolePage.values
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _NavPill(
                        label: _ShellLabels.label(entry),
                        selected: page == entry,
                        onTap: () => onPageSelected(entry),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: body,
            ),
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.page, required this.onPageSelected});

  final ConsolePage page;
  final ValueChanged<ConsolePage> onPageSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF25201B), Color(0xFF3A3128)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Brand(),
            const SizedBox(height: 18),
            for (final item in ConsolePage.values) ...[
              _NavItem(
                label: _ShellLabels.label(item),
                selected: page == item,
                onTap: () => onPageSelected(item),
              ),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            const Text(
              'MVP HTML shell now,\nFlutter Web later.',
              style: TextStyle(
                color: Color(0x99F7F1E9),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1F4A3C2A))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.brown.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          const _StatusChip(),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x194A3C2A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: Color(0xFF4FD17B)),
          SizedBox(width: 8),
          Text(
            'System healthy',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B6258)),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 0,
            spreadRadius: 5,
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'XWorkspace',
          style: TextStyle(
            color: Color(0xFFF7F1E9),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'AI Workspace Control Plane',
          style: TextStyle(color: Color(0x99F7F1E9), fontSize: 12),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0x1FFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: const Color(0x14FFFFFF)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xD0F7F1E9),
                  fontSize: 14,
                ),
              ),
            ),
            _Dot(
              color: selected
                  ? const Color(0xFF78D27F)
                  : const Color(0x33FFFFFF),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xFFE4EAF8)
            : Colors.white.withValues(alpha: 0.72),
        foregroundColor: selected
            ? const Color(0xFF2459C9)
            : const Color(0xFF4B4238),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }
}

class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('workspace'),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
      children: const [
        _OverviewGrid(),
        SizedBox(height: 18),
        _TerminalCard(
          title: 'Embedded Terminal',
          subtitle: 'ttyd placeholder for the live shell experience',
        ),
      ],
    );
  }
}

class OpenClawPage extends StatelessWidget {
  const OpenClawPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('openclaw'),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
      children: const [
        _TwoPanel(
          left: _MetricCardGrid(
            title: 'OpenClaw Gateway',
            subtitle: 'Ingress, authorization, and routing status',
            cards: [
              _MetricData('Requests', '1.8M', '24h total'),
              _MetricData('Errors', '0.2%', 'rolling avg'),
              _MetricData('P95', '142ms', 'response time'),
              _MetricData('Auth', 'OK', 'vault-linked'),
            ],
          ),
          right: _ServicePanel(
            title: 'Bridge',
            subtitle: 'Active sessions and shell bridging',
            rows: [
              _ServiceRow('ttyd channel', 'Connected sessions', '12 live'),
              _ServiceRow('Workspace sync', 'State propagation', 'Healthy'),
              _ServiceRow('Event queue', 'Backlog', '0 pending'),
            ],
          ),
        ),
      ],
    );
  }
}

class ModelPage extends StatelessWidget {
  const ModelPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('litellm'),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
      children: const [_ModelsCard()],
    );
  }
}

class VaultPage extends StatelessWidget {
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('vault'),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
      children: const [
        _TwoPanel(
          left: _MetricCardGrid(
            title: 'Vault',
            subtitle: 'Secrets, token rotation, and access policy',
            cards: [
              _MetricData('Secrets', '42', 'active items'),
              _MetricData('Rotations', '7d', 'next cycle'),
              _MetricData('Scopes', '5', 'policy groups'),
              _MetricData('Alerts', '0', 'open issues'),
            ],
          ),
          right: _TerminalCard(
            title: 'Terminal',
            subtitle: 'Minimal shell access entry point',
            compactHeight: 240,
            headerOnly: true,
          ),
        ),
      ],
    );
  }
}

class TerminalPage extends StatelessWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('terminal'),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
      children: const [
        _TerminalCard(
          title: 'Embedded Terminal',
          subtitle: 'Dedicated shell screen for ttyd integration',
          compactHeight: 520,
        ),
      ],
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 980;
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            SizedBox(
              width: narrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 18) * 0.58,
              child: const _ServicePanel(
                title: 'Services',
                subtitle: 'OpenClaw Gateway, Bridge, LiteLLM, Vault',
                rows: [
                  _ServiceRow(
                    'OpenClaw Gateway',
                    'Policy + ingress layer',
                    'Running',
                  ),
                  _ServiceRow('Bridge', 'Workspace session bridge', 'Running'),
                  _ServiceRow('LiteLLM', 'Model router and proxy', 'Running'),
                  _ServiceRow(
                    'Vault',
                    'Secrets and credential store',
                    'Running',
                  ),
                ],
              ),
            ),
            SizedBox(
              width: narrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 18) * 0.40,
              child: const _MetricCardGrid(
                title: 'Runtime',
                subtitle: 'Capacity and health snapshot',
                cards: [
                  _MetricData('CPU', '18%', 'steady load'),
                  _MetricData('Memory', '4.1G', '/ 8G used'),
                  _MetricData('Disk', '23G', '/ 80G used'),
                  _MetricData('Uptime', '12d', '2h 41m'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TwoPanel extends StatelessWidget {
  const _TwoPanel({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 980;
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            SizedBox(
              width: narrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 18) * 0.58,
              child: left,
            ),
            SizedBox(
              width: narrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 18) * 0.40,
              child: right,
            ),
          ],
        );
      },
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x194A3C2A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x144F371B),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.brown.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }
}

class _ServicePanel extends StatelessWidget {
  const _ServicePanel({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final List<_ServiceRow> rows;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: [
          for (final row in rows) ...[
            _ServiceTile(row: row),
            if (row != rows.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MetricCardGrid extends StatelessWidget {
  const _MetricCardGrid({
    required this.title,
    required this.subtitle,
    required this.cards,
  });

  final String title;
  final String subtitle;
  final List<_MetricData> cards;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: title,
      subtitle: subtitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 420;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final item in cards)
                SizedBox(
                  width: narrow
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 14) / 2,
                  child: _MetricTile(data: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ModelsCard extends StatelessWidget {
  const _ModelsCard();

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Models',
      subtitle: 'Future LiteLLM view with latency, RPM, and cost',
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search model, provider, status...',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.78),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x194A3C2A)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x194A3C2A)),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(0.8),
              3: FlexColumnWidth(0.7),
              4: FlexColumnWidth(0.8),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              _headerRow(),
              _modelRow('GPT-5', 'Ready', '128 ms', '620', '\$0.00 / req'),
              _modelRow('Claude', 'Ready', '145 ms', '540', '\$0.00 / req'),
              _modelRow('Gemini', 'Ready', '132 ms', '480', '\$0.00 / req'),
              _modelRow('DeepSeek', 'Ready', '160 ms', '510', '\$0.00 / req'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({
    required this.title,
    required this.subtitle,
    this.compactHeight = 220,
    this.headerOnly = false,
  });

  final String title;
  final String subtitle;
  final double compactHeight;
  final bool headerOnly;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: title,
      subtitle: subtitle,
      child: Container(
        height: compactHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF141619),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        padding: const EdgeInsets.all(18),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Color(0xFFCCF6CC),
            height: 1.5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'ubuntu@workspace:~\$',
                      style: TextStyle(color: Color(0xFF7DD9A2)),
                    ),
                    TextSpan(
                      text: ' openclaw status',
                      style: TextStyle(color: Color(0xFFB3CBB8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Gateway      Running',
                style: TextStyle(color: Color(0xFFB3CBB8)),
              ),
              const Text(
                'Bridge       Running',
                style: TextStyle(color: Color(0xFFB3CBB8)),
              ),
              const Text(
                'LiteLLM      Running',
                style: TextStyle(color: Color(0xFFB3CBB8)),
              ),
              const Text(
                'Vault        Running',
                style: TextStyle(color: Color(0xFFB3CBB8)),
              ),
              if (!headerOnly) const Spacer(),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'ubuntu@workspace:~\$',
                      style: TextStyle(color: Color(0xFF7DD9A2)),
                    ),
                    TextSpan(
                      text: ' _',
                      style: TextStyle(color: Color(0xFFB3CBB8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x144A3C2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6D645B)),
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.subtext,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6D645B)),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.row});

  final _ServiceRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x144A3C2A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6D645B),
                  ),
                ),
              ],
            ),
          ),
          _Badge(label: row.status),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color:
            label.toLowerCase().contains('running') ||
                label.toLowerCase().contains('ready')
            ? const Color(0x1A2C8F57)
            : const Color(0x1AE3A93A),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label == 'Running' ? '● Running' : label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color:
              label.toLowerCase().contains('running') ||
                  label.toLowerCase().contains('ready')
              ? const Color(0xFF2C8F57)
              : const Color(0xFF946600),
        ),
      ),
    );
  }
}

TableRow _headerRow() {
  return const TableRow(
    children: [
      _HeaderCell('Model'),
      _HeaderCell('Status'),
      _HeaderCell('Latency'),
      _HeaderCell('RPM'),
      _HeaderCell('Cost'),
    ],
  );
}

TableRow _modelRow(
  String model,
  String status,
  String latency,
  String rpm,
  String cost,
) {
  return TableRow(
    children: [
      _TableCell(
        Text(
          model,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      _TableCell(_Badge(label: status)),
      _TableCell(Text(latency)),
      _TableCell(Text(rpm)),
      _TableCell(Text(cost)),
    ],
  );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF6D645B),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: child,
    );
  }
}

class _ShellLabels {
  static String label(ConsolePage page) {
    return switch (page) {
      ConsolePage.workspace => 'Workspace',
      ConsolePage.openclaw => 'OpenClaw',
      ConsolePage.litellm => 'LiteLLM',
      ConsolePage.vault => 'Vault',
      ConsolePage.terminal => 'Terminal',
    };
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.subtext);

  final String label;
  final String value;
  final String subtext;
}

class _ServiceRow {
  const _ServiceRow(this.title, this.subtitle, this.status);

  final String title;
  final String subtitle;
  final String status;
}
