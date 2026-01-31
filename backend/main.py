from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import chess

app = FastAPI()

piece_values = {
    chess.PAWN: 1,    #piyon
    chess.KNIGHT: 3,  #at
    chess.BISHOP: 3,  #fil
    chess.ROOK: 5,    #kale
    chess.QUEEN: 9,   #vezir$env:Path -split ';' | Select-String "flutter\\bin"*

    chess.KING: 0     #şah
}

def evaluate(board: chess.Board) -> int: # Basit materyal değerlendirmesi
    score = 0
    for piece, val in piece_values.items():
        score += len(board.pieces(piece, chess.WHITE)) * val
        score -= len(board.pieces(piece, chess.BLACK)) * val
    return score

def minimax(board: chess.Board, depth: int, alpha: int, beta: int, maximizing: bool) -> int:
#depth kaç hamle ileri bakılacak, alpha beyazın en iyi skoru, beta siyahın en iyi skoru, maximizing beyaz mı oynuyor
    if depth == 0 or board.is_game_over():
        return evaluate(board) #eğer derinlik 0 ise veya oyun bitti ise değerlendirme fonksiyonunu çağır

    if maximizing:
        max_eval = -10**9                                        #çok düşük bir başlangıç skoru(isteğe bağlı)
        for move in board.legal_moves:                           #tüm yasal hamleler için
            board.push(move)                                     #hamleyi yap
            ev = minimax(board, depth - 1, alpha, beta, False)   #sonraki hamle için minimax çağır
            board.pop()                                          #hamleyi geri al
            if ev > max_eval:                                    #en iyi skoru güncelle
                max_eval = ev                                    
            if ev > alpha:                                       #alpha'yı güncelle 
                alpha = ev
            if beta <= alpha:                                    #alpha-beta pruning
                break 
        return max_eval
    else:                                                       # minimizing player (siyah)
        min_eval = 10**9                                        #çok yüksek bir başlangıç skoru(isteğe bağlı)
        for move in board.legal_moves:                          #tüm yasal hamleler için
            board.push(move)                                    #hamleyi yap
            ev = minimax(board, depth - 1, alpha, beta, True)   #sonraki hamle için minimax çağır
            board.pop()                                         #hamleyi geri al
            if ev < min_eval:                                   #en iyi skoru güncelle
                min_eval = ev
            if ev < beta:                                       #beta'yı güncelle
                beta = ev
            if beta <= alpha:                                   #alpha-beta pruning
                break
        return min_eval

def best_move(board: chess.Board, depth: int = 3) -> chess.Move | None:
    best = None
    best_value = -10**9

    # Sıra kimdeyse ona göre maximize/minimize yap
    maximizing = (board.turn == chess.WHITE)

    for move in board.legal_moves:                                      #tüm yasal hamleler için
        board.push(move)                                                #hamleyi yap
        value = minimax(board, depth - 1, -10**9, 10**9, not maximizing)#minimax çağır
        board.pop()                                                     #hamleyi geri al

        if maximizing:                       # beyaz oynuyorsa daha yüksek skor tercih eder
            if value > best_value:           #en iyi skoru güncelle
                best_value = value 
                best = move
        else:
            # siyah oynuyorsa daha düşük skor (beyaz avantajını azaltır) tercih eder
            if best is None or value < best_value:
                best_value = value
                best = move

    return best

class NewGameResponse(BaseModel):   #yeni oyun başlatma yanıt modeli
    fen: str

class PlayRequest(BaseModel):
    fen: str
    user_move: str  # UCI, örn: "e2e4"
    depth: int = 3

class PlayResponse(BaseModel):    #oyun oynama yanıt modeli
    user_move: str
    ai_move: str | None
    fen_before: str
    fen_after_user: str
    fen_after_ai: str
    game_over: bool
    result: str | None            # "1-0", "0-1", "1/2-1/2" gibi

@app.post("/new_game", response_model=NewGameResponse)  #yeni oyun başlatma uç noktası
def new_game():                                         #yeni oyun başlat
    b = chess.Board()                                   #başlangıç pozisyonu
    return {"fen": b.fen()}                             #FEN döndür

@app.post("/play", response_model=PlayResponse)         #oyun oynama uç noktası
def play(req: PlayRequest):                             #hamle yap
    board = chess.Board(req.fen)                        #gönderilen FEN ile tahtayı oluştur
    fen_before = board.fen()                            #hamle öncesi FEN

    try:               # Kullanıcının hamlesini UCI formatında al
        user = chess.Move.from_uci(req.user_move)
    except ValueError: # Geçersiz hamle formatı
        raise HTTPException(status_code=400, detail="Invalid move format. Use UCI like e2e4.")

    if user not in board.legal_moves: # Hamle yasal mı kontrol et
        raise HTTPException(status_code=400, detail="Illegal move.")

    board.push(user)                  # Kullanıcının hamlesini yap
    fen_after_user = board.fen()      # Hamle sonrası FEN

    if board.is_game_over():          # Oyun bitti mi kontrol et
        return {
            "user_move": req.user_move,        # Kullanıcının hamlesi
            "ai_move": None,                   # AI hamlesi yok
            "fen_before": fen_before,          # Hamle öncesi FEN
            "fen_after_user": fen_after_user,  # Kullanıcının hamlesi sonrası FEN
            "fen_after_ai": fen_after_user,    # AI hamlesi sonrası FEN (değişmedi)
            "game_over": True,                 # Oyun bitti
            "result": board.result()           # Oyun sonucu
        }

    ai = best_move(board, depth=req.depth)     # AI'nin en iyi hamlesini bul
    if ai is None:                             # AI hamlesi yoksa (beraberlik durumu)
        return {  
            "user_move": req.user_move,        # Kullanıcının hamlesi
            "ai_move": None,                   # AI hamlesi yok
            "fen_before": fen_before,          # Hamle öncesi FEN
            "fen_after_user": fen_after_user,  # Kullanıcının hamlesi sonrası FEN
            "fen_after_ai": fen_after_user,    # AI hamlesi sonrası FEN (değişmedi)
            "game_over": True,                 # Oyun bitti
            "result": board.result()           # Oyun sonucu
        }

    board.push(ai)                            # AI'nin hamlesini yap
    fen_after_ai = board.fen()                # AI hamlesi sonrası FEN

    return { 
        "user_move": req.user_move,
        "ai_move": ai.uci(),
        "fen_before": fen_before,
        "fen_after_user": fen_after_user,
        "fen_after_ai": fen_after_ai,
        "game_over": board.is_game_over(),
        "result": board.result() if board.is_game_over() else None    #oyun sonucu
    }
