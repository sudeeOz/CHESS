from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
import chess
import re
import random

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:63135",
        "http://127.0.0.1:63135",
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "*",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------
# Evaluation / minimax
# -----------------------------
piece_values = {
    chess.PAWN: 1,    # piyon
    chess.KNIGHT: 3,  # at
    chess.BISHOP: 3,  # fil
    chess.ROOK: 5,    # kale
    chess.QUEEN: 9,   # vezir
    chess.KING: 0     # şah
}

def evaluate(board: chess.Board) -> int:
    score = 0
    for piece, val in piece_values.items():
        score += len(board.pieces(piece, chess.WHITE)) * val
        score -= len(board.pieces(piece, chess.BLACK)) * val
    return score

def minimax(board: chess.Board, depth: int, alpha: int, beta: int, maximizing: bool) -> int:
    if depth == 0 or board.is_game_over():
        return evaluate(board)

    if maximizing:
        max_eval = -10**9
        for move in board.legal_moves:
            board.push(move)
            ev = minimax(board, depth - 1, alpha, beta, False)
            board.pop()
            if ev > max_eval:
                max_eval = ev
            if ev > alpha:
                alpha = ev
            if beta <= alpha:
                break
        return max_eval
    else:
        min_eval = 10**9
        for move in board.legal_moves:
            board.push(move)
            ev = minimax(board, depth - 1, alpha, beta, True)
            board.pop()
            if ev < min_eval:
                min_eval = ev
            if ev < beta:
                beta = ev
            if beta <= alpha:
                break
        return min_eval

def best_move(board: chess.Board, depth: int = 3) -> chess.Move | None:
    legal = list(board.legal_moves)
    if not legal:
        return None

    random.shuffle(legal)

    maximizing = (board.turn == chess.WHITE)

    if maximizing:
        best_val = -10**9
        best = legal[0]
        for mv in legal:
            board.push(mv)
            val = minimax(board, depth - 1, -10**9, 10**9, False)
            board.pop()
            if val > best_val:
                best_val = val
                best = mv
        return best
    else:
        best_val = 10**9
        best = legal[0]
        for mv in legal:
            board.push(mv)
            val = minimax(board, depth - 1, -10**9, 10**9, True)
            board.pop()
            if val < best_val:
                best_val = val
                best = mv
        return best

# -----------------------------
# Move parsing (SAN + UCI)
# -----------------------------
UCI_RE = re.compile(r"^[a-h][1-8][a-h][1-8][qrbn]?$", re.IGNORECASE)

def parse_move(board: chess.Board, move_str: str) -> chess.Move:
    s = move_str.strip()
    s = re.sub(r"^\d+\.\s*", "", s)  # "1. Nf3" -> "Nf3"

    if UCI_RE.match(s):
        return chess.Move.from_uci(s.lower())
    return board.parse_san(s)

# -----------------------------
# Scoring (1-10) + hint best move
# -----------------------------
def score_move_1_to_10(board: chess.Board, user_mv: chess.Move, depth: int) -> tuple[int, str]:
    """
    Kullanıcı hamlesini 1–10 puanla.
    - En iyi hamle değerini bul (best_val)
    - Kullanıcı hamle değerini bul (user_val)
    - Farka göre 1-10'a map et
    Dönen: (puan, best_move_uci)
    """
    maximizing = (board.turn == chess.WHITE)

    # Best move/value
    best = None
    best_val = -10**9 if maximizing else 10**9

    for mv in board.legal_moves:
        board.push(mv)
        val = minimax(board, depth - 1, -10**9, 10**9, not maximizing)
        board.pop()

        if maximizing:
            if val > best_val:
                best_val = val
                best = mv
        else:
            if val < best_val:
                best_val = val
                best = mv

    if best is None:
        return (5, "")

    # User move value
    board.push(user_mv)
    user_val = minimax(board, depth - 1, -10**9, 10**9, not maximizing)
    board.pop()

    # diff: kullanıcı ne kadar kötü?
    diff = (best_val - user_val) if maximizing else (user_val - best_val)

    # Evaluate küçük sayılar ürettiği için eşikler küçük tutuldu:
    if diff <= 0:
        score = 10
    elif diff <= 1:
        score = 9
    elif diff <= 2:
        score = 8
    elif diff <= 3:
        score = 7
    elif diff <= 4:
        score = 6
    elif diff <= 5:
        score = 5
    elif diff <= 6:
        score = 4
    elif diff <= 8:
        score = 3
    elif diff <= 10:
        score = 2
    else:
        score = 1

    return (score, best.uci())

# -----------------------------
# API Models
# -----------------------------
class NewGameResponse(BaseModel):
    fen: str

class PlayRequest(BaseModel):
    fen: str
    user_move: str      # SAN veya UCI
    depth: int = 3

class PlayResponse(BaseModel):
    user_move: str
    ai_move: str | None
    fen_before: str
    fen_after_user: str
    fen_after_ai: str
    game_over: bool
    result: str | None
    user_score: int | None = None
    hint_best_uci: str | None = None

class HintRequest(BaseModel):
    fen: str
    depth: int = 3

class HintResponse(BaseModel):
    best_uci: str

# -----------------------------
# Routes
# -----------------------------
@app.post("/new_game", response_model=NewGameResponse)
def new_game():
    b = chess.Board()
    return {"fen": b.fen()}

@app.post("/play", response_model=PlayResponse)
def play(req: PlayRequest):
    board = chess.Board(req.fen)
    fen_before = board.fen()

    # Parse (SAN + UCI)
    try:
        user = parse_move(board, req.user_move)
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Invalid move format. Use UCI like e2e4 or SAN like Nf3."
        )

    # Legal?
    if user not in board.legal_moves:
        raise HTTPException(status_code=400, detail="Illegal move.")

    # Score + best hint (user move uygulanmadan önce)
    user_score, hint_best_uci = score_move_1_to_10(board, user, req.depth)

    # Apply user move
    board.push(user)
    fen_after_user = board.fen()

    # If game over after user
    if board.is_game_over():
        return {
            "user_move": req.user_move,
            "ai_move": None,
            "fen_before": fen_before,
            "fen_after_user": fen_after_user,
            "fen_after_ai": fen_after_user,
            "game_over": True,
            "result": board.result(),
            "user_score": user_score,
            "hint_best_uci": hint_best_uci,
        }

    # AI move
    ai = best_move(board, depth=req.depth)
    if ai is None:
        return {
            "user_move": req.user_move,
            "ai_move": None,
            "fen_before": fen_before,
            "fen_after_user": fen_after_user,
            "fen_after_ai": fen_after_user,
            "game_over": True,
            "result": board.result(),
            "user_score": user_score,
            "hint_best_uci": hint_best_uci,
        }

    board.push(ai)
    fen_after_ai = board.fen()

    return {
        "user_move": req.user_move,
        "ai_move": ai.uci(),
        "fen_before": fen_before,
        "fen_after_user": fen_after_user,
        "fen_after_ai": fen_after_ai,
        "game_over": board.is_game_over(),
        "result": board.result() if board.is_game_over() else None,
        "user_score": user_score,
        "hint_best_uci": hint_best_uci,
    }

@app.post("/hint", response_model=HintResponse)
def hint(req: HintRequest):
    board = chess.Board(req.fen)
    mv = best_move(board, depth=req.depth)
    if mv is None:
        raise HTTPException(status_code=400, detail="No legal moves")
    return {"best_uci": mv.uci()}
