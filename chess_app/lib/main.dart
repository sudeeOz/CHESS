import 'package:flutter/material.dart' hide Color;
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'api_service.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

void main() => runApp(const MyApp());

class MoveEntry {
  final int no;
  final String moveSan;
  final int? score;

  MoveEntry({required this.no, required this.moveSan, required this.score});
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final api = ChessApi("http://127.0.0.1:8000");
  late ChessBoardController controller;

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  String status = "Yükleniyor...";
  bool loading = false;

  String lastFenBeforeMove = "";

  int aiDepth = 3;
  bool difficultyLocked = false;
  bool gameOver = false;

  final List<MoveEntry> myMoves = [];

  String? hintedUci;

  @override
  void initState() {
    super.initState();
    controller = ChessBoardController();
    startNewGame();
  }

  // tahtanın kenarındaki sayılar (1-8)
  Widget _rankLabelsColumn({bool reverse = false, required double height}) {
    final ranks = ["1", "2", "3", "4", "5", "6", "7", "8"];
    final list = reverse ? ranks.reversed.toList() : ranks;

    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final r in list)
            Text(
              r,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ui.Color(0xFF616161),
              ),
            ),
        ],
      ),
    );
  }

  // tahtanın kenarındaki harfler (a-h)
  Widget _fileLabelsRowSized(double width) {
    final files = ["a", "b", "c", "d", "e", "f", "g", "h"];

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final f in files)
              Text(
                f,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ui.Color(0xFF616161),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Oyun işlemleri
  Future<void> startNewGame() async {
    setState(() {
      loading = true;
      status = "Yeni oyun başlatılıyor...";
      gameOver = false;
      difficultyLocked = false;
      hintedUci = null;
    });

    try {
      final fen = await api.newGame();
      if (!mounted) return;

      controller.loadFen(fen);
      lastFenBeforeMove = fen;
      myMoves.clear();

      setState(() => status = "Hamle yap!");
    } catch (e) {
      if (!mounted) return;
      setState(() => status = "Bağlantı hatası: $e");
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> showHint() async {
    if (loading || gameOver) return;

    setState(() {
      loading = true;
      status = "İpucu hazırlanıyor...";
    });

    try {
      final bestUci = await api.hint(
        fen: lastFenBeforeMove,
        depth: aiDepth,
      );
      if (!mounted) return;

      setState(() {
        hintedUci = bestUci;
        status = "Hamle yap!";
      });

      final ctx = _navKey.currentContext;
      if (ctx == null) return;

      showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          backgroundColor: const ui.Color(0xFF243447),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lightbulb, color: ui.Color(0xFFFFD54F)),
              SizedBox(width: 10),
              Text(
                "İpucu",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Text(
            "Bu pozisyonda en iyi hamle (UCI):\n\n$bestUci\n\nTahtada renkli olarak işaretlendi.",
            style: const TextStyle(
              color: ui.Color(0xFFECEFF1),
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: const ui.Color(0xFF243447),
                backgroundColor: const ui.Color(0xFFFFD54F),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Tamam", style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => status = "İpucu hatası: $e");
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> onUserMoved() async {
    if (loading || gameOver) return;

    final sanList = controller.getSan();
    final lastSan = sanList.isNotEmpty ? sanList.last : null;
    if (lastSan == null || lastSan.trim().isEmpty) return;

    final fenToSend = lastFenBeforeMove;

    setState(() {
      loading = true;
      status = "Sanal oyuncu düşünüyor...";
      hintedUci = null;
    });

    try {
      final r = await api.play(
        fen: fenToSend,
        userMove: lastSan,
        depth: aiDepth,
      );
      if (!mounted) return;

      controller.loadFen(r.fen);
      lastFenBeforeMove = r.fen;

      myMoves.add(
        MoveEntry(no: myMoves.length + 1, moveSan: lastSan, score: r.userScore),
      );

      setState(() {
        gameOver = r.gameOver;
        status = gameOver ? "Oyun bitti: ${r.result ?? ''}" : "Hamle yap!";
      });
    } catch (e) {
      if (!mounted) return;
      if (lastFenBeforeMove.isNotEmpty) {
        controller.loadFen(lastFenBeforeMove);
      }
      setState(() => status = "Hata: $e");
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  // Kenar paneller
  Widget _panelContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: ui.Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _leftDifficultyPanel() {
    return _panelContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.speed_rounded, size: 18, color: ui.Color(0xFF2C3E50)),
              SizedBox(width: 8),
              Text("Zorluk", style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: aiDepth,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text("Kolay (1)")),
              DropdownMenuItem(value: 2, child: Text("Kolay (2)")),
              DropdownMenuItem(value: 3, child: Text("Orta (3)")),
              DropdownMenuItem(value: 4, child: Text("Zor (4)")),
              DropdownMenuItem(value: 5, child: Text("Çok Zor (5)")),
            ],
            onChanged: (loading || difficultyLocked)
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() {
                      aiDepth = v;
                      difficultyLocked = true;
                    });
                  },
          ),
        ],
      ),
    );
  }

  Widget _rightHintAndMovesPanel() {
    return _panelContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: (loading || gameOver) ? null : showHint,
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text("İpucu ister misin?"),
          ),
          const SizedBox(height: 12),
          const Text("Hamlelerim (Puan 1-10)", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: myMoves.length,
              itemBuilder: (context, i) {
                final m = myMoves[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text("${m.no}. ${m.moveSan}"),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const ui.Color(0xFFEFEFEF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      m.score?.toString() ?? "-",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Görünüm
 @override
Widget build(BuildContext context) {
  const double sidePanelWidth = 230;

  return MaterialApp(
    navigatorKey: _navKey,
    debugShowCheckedModeBanner: false,

    // ✅ Mavi/koyu bar + genel tema geri geldi
    theme: ThemeData(
      primarySwatch: Colors.blue,
      scaffoldBackgroundColor: const ui.Color(0xFFF5F5F5),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: ui.Color(0xFF2C3E50), // koyu mavi bar
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    ),

    home: Scaffold(
      appBar: AppBar(
        // ✅ Eski başlık tasarımın
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology, size: 26, color: Colors.white),
            SizedBox(width: 10),
            Text("Sanal Rakip"),
          ],
        ),
        actions: [
          IconButton(
            onPressed: (loading || gameOver) ? null : showHint,
            icon: const Icon(Icons.lightbulb_outline),
            tooltip: "İpucu",
          ),
          IconButton(
            onPressed: loading ? null : startNewGame,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Yeni Oyun",
          ),
          const SizedBox(width: 6),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 16),
                SizedBox(width: sidePanelWidth, child: _leftDifficultyPanel()),
                const SizedBox(width: 14),
                Expanded(child: Center(child: _buildBoardCard())),
                const SizedBox(width: 14),
                SizedBox(width: sidePanelWidth, child: _rightHintAndMovesPanel()),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Tahta kartı
  Widget _buildBoardCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 650),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, cons) {
          final double cardW = cons.maxWidth;
          final double cardH = cons.maxHeight.isFinite ? cons.maxHeight : 520.0;

          const double fileLabelH = 18.0;
          const double gap = 6.0;

          const double rankW = 18.0;
          const double rankGap = 6.0;
          final double extraW = rankW + rankGap + rankGap + rankW;

          final double maxSquareByH = cardH - (fileLabelH * 2) - (gap * 4);
          final double maxSquareByW = cardW - extraW;

          final double squareSide = math.min(maxSquareByH, maxSquareByW).toDouble();
          final double rankHeight = squareSide;

          return Center(
            child: SizedBox(
              width: squareSide + extraW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: gap),
                  _fileLabelsRowSized(squareSide),
                  const SizedBox(height: gap),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: rankW,
                        child: _rankLabelsColumn(reverse: true, height: rankHeight),
                      ),
                      const SizedBox(width: rankGap),

                      SizedBox(
                        width: squareSide,
                        height: squareSide,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ChessBoard(
                                controller: controller,
                                enableUserMoves: !loading && !gameOver,
                                onMove: () => onUserMoved(),
                                boardColor: BoardColor.darkBrown,
                              ),
                            ),
                            if (hintedUci != null && hintedUci!.length >= 4)
                              IgnorePointer(
                                child: CustomPaint(
                                  size: Size.square(squareSide),
                                  painter: _HintSquaresPainter(uci: hintedUci!),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(width: rankGap),
                      SizedBox(
                        width: rankW,
                        child: _rankLabelsColumn(reverse: true, height: rankHeight),
                      ),
                    ],
                  ),

                  const SizedBox(height: gap),
                  _fileLabelsRowSized(squareSide),
                  const SizedBox(height: gap),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HintSquaresPainter extends CustomPainter {
  final String uci;
  _HintSquaresPainter({required this.uci});

  @override
  void paint(Canvas canvas, Size size) {
    if (uci.length < 4) return;

    final from = _squareToXY(uci.substring(0, 2));
    final to = _squareToXY(uci.substring(2, 4));
    if (from == null || to == null) return;

    final cell = size.width / 8.0;

    Rect rectFor(Offset xy) =>
        Rect.fromLTWH(xy.dx * cell, xy.dy * cell, cell, cell);

    final paintFrom = Paint()
      ..color = const ui.Color(0x66FFD54F)
      ..style = PaintingStyle.fill;

    final paintTo = Paint()
      ..color = const ui.Color(0x664CAF50)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = const ui.Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rFrom = rectFor(from);
    final rTo = rectFor(to);

    canvas.drawRect(rFrom, paintFrom);
    canvas.drawRect(rTo, paintTo);
    canvas.drawRect(rFrom.deflate(1), stroke);
    canvas.drawRect(rTo.deflate(1), stroke);
  }

  Offset? _squareToXY(String sq) {
    if (sq.length != 2) return null;
    const files = "abcdefgh";
    final fx = files.indexOf(sq[0]);
    final r = int.tryParse(sq[1]);
    if (fx < 0 || r == null || r < 1 || r > 8) return null;

    final y = 7 - (r - 1);
    return Offset(fx.toDouble(), y.toDouble());
  }

  @override
  bool shouldRepaint(covariant _HintSquaresPainter oldDelegate) =>
      oldDelegate.uci != uci;
}
