module chess_engine.repr.state;

import chess_engine.repr.board;
import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.exception;
import std.math : abs;
import std.range;
import std.string;

struct GameState {
    Board board;
    Player turn;
    Castling castling;
    MCoord enPassant;
    ushort halfMove;
    ushort fullMove;
}

bool isInCheck(const ref GameState state, Player playerToCheck) {
    return false;
}

GameState parseFen(string input) {
    GameState fen;
    auto parts = input.strip.splitter(' ').staticArray!6;
    foreach (rank, line; parts[0].splitter('/').enumerate) {
        auto file = 0;
        foreach (c; line) {
            if (c.isDigit) {
                file += c - '0';
                continue;
            }
            enforce(c.isAlpha);
            Player player = c.isLower ? Player.black : Player.white;
            Piece piece;
        sw:
            switch (std.ascii.toLower(c)) {
                static foreach (v; pieceByFenName) {
            case v[0]:
                    piece = v[1];
                    break sw;
                }
            default:
                break;
            }
            enforce(file < 8 && rank < 8);
            *fen.board.getSquare(file, 7 - rank) = Square(player, piece);
            ++file;
        }
    }

    fen.turn = parts[1][0] == 'b' ? Player.black : Player.white;
    string castling = parts[2];
    fen.castling = Castling.none;
    foreach (c; castling) {
        switch (c) {
        case 'K':
            fen.castling.king[Player.white] = 1;
            break;
        case 'Q':
            fen.castling.queen[Player.white] = 1;
            break;
        case 'k':
            fen.castling.king[Player.black] = 1;
            break;
        case 'q':
            fen.castling.queen[Player.black] = 1;
            break;
        default:
            break;
        }
    }
    if (parts[3] == "-") {
        fen.enPassant = MCoord.invalid;
    } else {
        fen.enPassant = MCoord(cast(ubyte)(parts[3][1] - '1'), cast(ubyte)(parts[3][0] - 'a'));
    }
    fen.halfMove = parts[4].to!ushort;
    fen.fullMove = parts[5].to!ushort;
    return fen;
}

string toFen(const ref GameState state) {
    auto builder = appender("");
    foreach (rank; iota(8).retro) {
        size_t numEmpty = 0;
        foreach (file; iota(8)) {
            auto square = state.board.getSquare(file, rank);
            if (square.isEmpty) {
                ++numEmpty;
                continue;
            }
            if (numEmpty > 0) {
                builder.put(numEmpty.to!string);
                numEmpty = 0;
            }
            builder.put(square.getRepr);
        }
        if (numEmpty > 0) {
            builder.put(numEmpty.to!string);
        }
        if (rank > 0) {
            builder.put('/');
        }
    }
    // Turn
    builder.put(state.turn == Player.black ? " b" : " w");
    // Castling
    builder.put(" ");
    if (state.castling == Castling.none) {
        builder.put("-");
    } else {
        foreach (c; "KQkq") {
            Player player = std.ascii.isLower(c) ? Player.black : Player.white;
            bool canCastle = std.ascii.toLower(c) == 'k'
                ? state.castling.king[player] : state.castling.queen[player];
            if (canCastle) {
                builder.put(c);
            }
        }
    }
    // En passant
    builder.put(" ");
    builder.put(state.enPassant == MCoord.invalid ? "-" : state.enPassant.getRepr);
    // Half and FullMove
    builder.put(" %d %d".format(state.halfMove, state.fullMove));
    return builder.data();
}

unittest {
    const boards = [
        "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
        "3k4/8/8/8/2B5/8/8/3K4 w - - 0 1",
        "3k4/8/8/8/2B5/8/8/3K4 w KQk - 0 1",
        "3k4/8/8/8/2B5/8/8/3K4 b KQk - 1 1",
        "3k4/8/8/8/2B5/8/8/3K4 w KQk - 2 2",
        "4k3/4p3/8/8/8/8/4P3/4K3 b KQkq - 0 1",
    ];
    foreach (board; boards) {
        auto parsed = board.parseFen;
        assert(parsed.toFen == board);
    }
}

unittest {
    auto parsed = "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2".parseFen;
    assert(*parsed.board.getSquare(5, 5) == Square());
    assert(*parsed.board.getSquare(0, 0) == Square(Player.white, Piece.rook));
    assert(parsed.turn == Player.black);
    assert(parsed.castling == Castling.all);
    assert(parsed.halfMove == 1);
    assert(parsed.fullMove == 2);
    assert(MCoord(3, 4).getRepr == "d5");
    assert(Move(MCoord(3, 4), MCoord(7, 0)).getRepr == "d5h1");
}

static ulong numEvals;

float leafEval(GameState state) {
    auto sum = 0.0;
    // TODO: One true source for this
    static const int[] VALUES = [0, 1, 5, 3, 3, 9, 4];
    foreach (rank; 0 .. 8) {
        foreach (file; 0 .. 8) {
            const auto square = state.board.getSquare(file, rank);
            auto piece = square.getPiece();
            if (piece == Piece.empty) {
                continue;
            }
            auto centerCoeff = abs(((rank / 3.5) - 1) * ((file / 3.5) - 1));
            if (piece != Piece.king) {
                centerCoeff = 1 - centerCoeff;
            }
            auto sign = square.getPlayer == Player.black ? -1 : 1;
            int value = VALUES[piece];
            sum += sign * value * (1 + .05 * centerCoeff);
        }
    }
    ++numEvals;
    return sum;
}

unittest {
    // KB > k, even if K close to center
    assert("8/8/8/3k4/8/8/4B3/3K4 w - - 0 1".parseFen.leafEval >= 0);
    // KB < kb if b closer to center
    assert("3k4/8/8/4b3/8/8/4B3/3K4 w - - 0 1".parseFen.leafEval <= 0);
    // KBB > kb
    assert("3k4/8/8/4b3/8/8/3BB3/3K4 w - - 0 1".parseFen.leafEval >= 0);
    // KQR > krr with rr close to center
    assert("3k4/8/8/3rr3/8/8/8/Q2K3R w - - 0 1".parseFen.leafEval > 0);
}
