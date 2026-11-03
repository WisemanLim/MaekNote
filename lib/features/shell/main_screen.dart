// maeknote — VOX 스타일 메인 화면 (헤더 · 제어줄 · 아이콘 탭 · 본문)
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/window_sizer.dart';

/// 상단 아이콘 탭. 라이브러리(Playlist·Collections) / 노트(전사·요약) / 모델.
enum MainTab { library, note, models }

/// 제어줄 토글로 본문을 대체하는 패널. (Image #2 EQ, Image #3 출력 장치)
enum OverlayPanel { none, equalizer, output }

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.header,
    required this.controls,
    required this.transport,
    required this.library,
    required this.note,
    required this.models,
    required this.equalizer,
    required this.output,
    this.onOpenSettings,
    this.notePanelOpen = false,
    this.onToggleNotePanel,
    this.noteRequest = 0,
  });

  final Widget header;
  final Widget Function(OverlayPanel panel, ValueChanged<OverlayPanel> toggle)
      controls;
  final Widget transport;
  final Widget library;
  final Widget note;
  final Widget models;
  final Widget equalizer;
  final Widget output;
  final VoidCallback? onOpenSettings;

  /// 데스크톱: 노트(전사·요약)를 플레이어 오른쪽 패널로 펼친 상태 (Image #8)
  final bool notePanelOpen;

  /// 지정되면 데스크톱 패널 방식 — 노트 아이콘이 오른쪽 패널을 열고 닫는다
  final VoidCallback? onToggleNotePanel;

  /// 값이 바뀌면 노트를 앞으로 (휴대폰: 노트 탭 선택)
  final int noteRequest;

  /// 모바일·태블릿: 이 너비 이상이면 노트를 오른쪽에 함께 표시
  static const wideBreakpoint = 900.0;

  /// 데스크톱 패널이 플레이어 옆에 놓이기 위한 최소 너비
  static const minPanelWidth = 280.0;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  MainTab _tab = MainTab.library;
  OverlayPanel _panel = OverlayPanel.none;

  void _toggle(OverlayPanel p) =>
      setState(() => _panel = _panel == p ? OverlayPanel.none : p);

  bool get _desktop => widget.onToggleNotePanel != null;

  @override
  void didUpdateWidget(MainScreen old) {
    super.didUpdateWidget(old);
    if (widget.noteRequest != old.noteRequest && !_desktop) {
      _tab = MainTab.note;
      _panel = OverlayPanel.none;
    }
  }

  Widget _body(bool wide) {
    switch (_panel) {
      case OverlayPanel.equalizer:
        return widget.equalizer;
      case OverlayPanel.output:
        return widget.output;
      case OverlayPanel.none:
        break;
    }
    switch (_tab) {
      case MainTab.library:
        return widget.library;
      case MainTab.note:
        return wide || _desktop ? widget.library : widget.note;
      case MainTab.models:
        return widget.models;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final split = _desktop
              ? widget.notePanelOpen &&
                  c.maxWidth >= playerWindowWidth + MainScreen.minPanelWidth
              : c.maxWidth >= MainScreen.wideBreakpoint;
          // 데스크톱에서 창이 좁아 나란히 둘 수 없으면 노트를 본문에 표시
          final noteInBody = _desktop && widget.notePanelOpen && !split;
          final wide = split;
          final player = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 헤더를 가리키면(터치: 누르면) 시크바·볼륨·반복·EQ 가 아래로 펼쳐진다
              HoverReveal(
                header: widget.header,
                revealed: widget.controls(_panel, _toggle),
                keepOpen: _panel != OverlayPanel.none,
              ),
              const Divider(height: 1),
              widget.transport,
              if (_panel == OverlayPanel.none) _tabBar(wide),
              const Divider(height: 1),
              Expanded(
                  child: noteInBody && _panel == OverlayPanel.none
                      ? widget.note
                      : _body(wide)),
            ],
          );
          if (!split) return player;
          return Row(children: [
            SizedBox(width: _desktop ? playerWindowWidth : 360, child: player),
            const VerticalDivider(width: 1),
            Expanded(child: widget.note),
          ]);
        }),
      ),
    );
  }

  Widget _tabBar(bool wide) {
    Widget item(MainTab tab, IconData icon, String label) {
      final noteToggle = _desktop && tab == MainTab.note;
      final selected = noteToggle ? widget.notePanelOpen : _tab == tab;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: InkWell(
            onTap: noteToggle
                ? widget.onToggleNotePanel
                : () => setState(() => _tab = tab),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? VoxColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Icon(icon,
                  color: selected ? VoxColors.accent : VoxColors.muted),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      item(MainTab.library, Icons.queue_music, context.tr('shell.library')),
      if (!wide || _desktop)
        item(MainTab.note, Icons.notes, context.tr('shell.note')),
      item(MainTab.models, Icons.memory, context.tr('shell.models')),
      Expanded(
        child: IconButton(
          tooltip: context.tr('app.settings'),
          icon: const Icon(Icons.settings, color: VoxColors.muted),
          onPressed: widget.onOpenSettings,
        ),
      ),
    ]);
  }
}

/// [header] 를 가리키는 동안 [revealed] 를 슬라이드로 펼친다 (VOX 헤더 방식).
/// 마우스가 없는 기기는 헤더를 눌러 열고 닫는다. [keepOpen] 이면 계속 펼침(EQ·출력 패널 사용 중).
class HoverReveal extends StatefulWidget {
  const HoverReveal({
    super.key,
    required this.header,
    required this.revealed,
    this.keepOpen = false,
  });

  final Widget header;
  final Widget revealed;
  final bool keepOpen;

  @override
  State<HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<HoverReveal> {
  bool _hover = false;
  bool _pinned = false;
  Timer? _close;

  void _enter() {
    _close?.cancel();
    if (!_hover) setState(() => _hover = true);
  }

  // 슬라이더를 끌다 잠깐 벗어나도 닫히지 않도록 조금 늦게 닫는다
  void _exit() {
    _close?.cancel();
    _close = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _hover = false);
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _hover || _pinned || widget.keepOpen;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _pinned = !_pinned),
              child: widget.header,
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: open ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              // 닫혀 있으면 키보드 포커스·스크린리더에서도 숨긴다
              child: ExcludeFocus(
                excluding: !open,
                child:
                    ExcludeSemantics(excluding: !open, child: widget.revealed),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
