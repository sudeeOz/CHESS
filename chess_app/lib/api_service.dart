import 'dart:convert';
import 'package:http/http.dart' as http;

class PlayResult {
  final String fen; // fen_after_ai
  final String? aiMove; // UCI
  final int? userScore; // 1-10
  final String? hintBestUci; // UCI
  final bool gameOver;
  final String? result;

  PlayResult({
    required this.fen,
    required this.aiMove,
    required this.userScore,
    required this.hintBestUci,
    required this.gameOver,
    required this.result,
  });
}

class ChessApi {
  final String baseUrl;
  ChessApi(this.baseUrl);

  Future<String> newGame() async {
    final res = await http.post(Uri.parse("$baseUrl/new_game"));
    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data["fen"].toString();
  }

  Future<PlayResult> play({
    required String fen,
    required String userMove,
    int depth = 3,
  }) async {
    final res = await http.post(
      Uri.parse("$baseUrl/play"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "fen": fen,
        "user_move": userMove,
        "depth": depth,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final fenAfterAi = (data["fen_after_ai"] ?? data["fen_after_user"]).toString();

    return PlayResult(
      fen: fenAfterAi,
      aiMove: data["ai_move"]?.toString(),
      userScore: data["user_score"] is int ? data["user_score"] as int : null,
      hintBestUci: data["hint_best_uci"]?.toString(),
      gameOver: data["game_over"] == true,
      result: data["result"]?.toString(),
    );
  }

  Future<String> hint({
    required String fen,
    int depth = 3,
  }) async {
    final res = await http.post(
      Uri.parse("$baseUrl/hint"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"fen": fen, "depth": depth}),
    );

    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data["best_uci"].toString();
  }
}
