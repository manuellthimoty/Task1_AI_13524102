:- set_prolog_flag(double_quotes, atom).
% ============================================================
%  core.pl - uji logika inti Connect-4 (papan, langkah, menang)
%  Papan: list 7 kolom; tiap kolom = list 6 sel [bawah..atas]
%  Sel: x, o, atau e (kosong)
% ============================================================

% -- deklarasi dynamic terpusat (semua predicate stateful proyek) --
:- dynamic(game_state/3).       % game_state(Board, Turn, Depth)
:- dynamic(player_type/2).      % player_type(x, human|ai), player_type(o, ...)
:- dynamic(diff_level/1).       % mudah | sedang | sulit | expert | custom
:- dynamic(ai_style/1).         % balanced | aggressive | defensive | random
:- dynamic(undo_stack/1).       % list snapshot s(Board,Turn,Depth) - undo
:- dynamic(redo_stack/1).       % list snapshot - redo
:- dynamic(move_log/1).         % list kolom yang sudah dimainkan
:- dynamic(last_pos/1).         % kolom langkah terakhir (penanda papan)
:- dynamic(stat/2).             % stat(xwin,N) / stat(owin,N) / stat(draw,N)
:- dynamic(rng_seed/1).         % seed PRNG (LCG)
:- dynamic(tt_entry/4).         % transposition table: tt_entry(Board,Player,Depth,Value)
:- dynamic(search_counter/2).   % search_counter(nodes|alpha_cut|beta_cut|tt_hit|tt_miss, N)
:- dynamic(book_move_fact/2).   % opening book: book_move_fact(MoveLogPrefix, Col)
:- dynamic(zobrist_val/4).      % zobrist_val(Col,Row,Piece,RandomInt)
:- dynamic(puzzle_fact/4).      % puzzle_fact(Id, Board, Turn, Deskripsi)
:- dynamic(replay_state/3).     % replay_state(Boards, Index, Moves) - replay interaktif

% -- inisialisasi papan kosong (7 kolom x 6 baris) --
empty_col([e,e,e,e,e,e]).

initial_board(Board) :-
    empty_col(C),
    Board = [C,C,C,C,C,C,C].

% -- akses sel: Col 1..7, Row 1..6 (gagal jika di luar batas) --
cell(Board, Col, Row, Val) :-
    nth1(Col, Board, Column),
    nth1(Row, Column, Val).

% -- langkah valid: kolom 1..7 dan belum penuh (sel teratas kosong) --
valid_move(Board, Col) :-
    between(1, 7, Col),
    cell(Board, Col, 6, e).

% -- jatuhkan bidak Player ke kolom Col --
drop(Board, Col, Player, NewBoard) :-
    nth1(Col, Board, Column),
    drop_in_col(Column, Player, NewColumn),
    replace_nth(Board, Col, NewColumn, NewBoard).

% cari sel 'e' terbawah lalu isi (REKURENS)
drop_in_col([e|Rest], Player, [Player|Rest]) :- !.
drop_in_col([X|Rest], Player, [X|NewRest]) :-
    X \== e,
    drop_in_col(Rest, Player, NewRest).

% ganti elemen ke-N sebuah list (REKURENS)
replace_nth([_|T], 1, New, [New|T]) :- !.
replace_nth([H|T], N, New, [H|T2]) :-
    N > 1, N1 is N - 1,
    replace_nth(T, N1, New, T2).

% -- deteksi menang: 4 sejajar (horizontal, vertikal, 2 diagonal) --
won(Board, P) :-
    member(P, [x, o]),                 % hanya x/o, jangan cocokkan sel kosong 'e'
    between(1, 7, C), between(1, 6, R),
    member((DC,DR), [(1,0),(0,1),(1,1),(1,-1)]),
    four(Board, P, C, R, DC, DR), !.

four(Board, P, C, R, DC, DR) :-
    cell(Board, C, R, P),
    C1 is C+DC,   R1 is R+DR,   cell(Board, C1, R1, P),
    C2 is C+2*DC, R2 is R+2*DR, cell(Board, C2, R2, P),
    C3 is C+3*DC, R3 is R+3*DR, cell(Board, C3, R3, P).

% -- papan penuh (seri) --
board_full(Board) :- \+ valid_move(Board, _).

% -- posisi berakhir: ada yang menang ATAU papan penuh --
terminal_like(Board) :- ( won(Board, x) ; won(Board, o) ; board_full(Board) ), !.

%  ai.pl - AI Connect-4: negamax + alpha-beta + fitur lanjutan
%  Konsep: REKURENS (negamax/nm_loop), LIST (papan, jendela,
%  Scored pairs), CUT (commit + beta cutoff), FAIL (immediate_win
%  pencarian via valid_move yang gagal utk kolom penuh)
% ============================================================

other(x, o).
other(o, x).

% urutan langkah center-first: main lebih kuat + pruning lebih efektif
ordered_moves(Board, Moves) :-
    findall(Col,
        ( member(Col, [4,3,5,2,6,1,7]), valid_move(Board, Col) ),
        Moves).

% ============================================================
%  Statistik pencarian (Nodes, Alpha/Beta Cutoff, TT hit/miss)
% ============================================================
reset_search_stats :-
    retractall(search_counter(_,_)),
    assertz(search_counter(nodes,0)),
    assertz(search_counter(alpha_cut,0)),
    assertz(search_counter(beta_cut,0)),
    assertz(search_counter(tt_hit,0)),
    assertz(search_counter(tt_miss,0)).

bump_counter(Key) :-
    ( retract(search_counter(Key,N)) -> N1 is N + 1 ; N1 = 1 ),
    assertz(search_counter(Key,N1)).

get_counter(Key, N) :- ( search_counter(Key,N) -> true ; N = 0 ).

% ============================================================
%  Transposition Table
%  Catatan desain: tabel dikosongkan di AWAL setiap panggilan
%  best_move_styled/5 (satu pencarian = satu langkah AI), bukan
%  dipertahankan sepanjang permainan. Ini sengaja: GNU Prolog
%  tidak mem-GC database secara otomatis, jadi menyimpan entri
%  lintas-langkah berisiko database membengkak tanpa batas pada
%  permainan panjang. Hanya nilai EXACT (hasil loop penuh tanpa
%  cutoff) yang di-cache; nilai hasil cutoff adalah BOUND, bukan
%  nilai pasti, sehingga tidak aman untuk dipakai ulang begitu saja.
% ============================================================
tt_store(Board, Player, Depth, Value) :-
    ( tt_entry(Board, Player, Depth, _) -> true
    ; assertz(tt_entry(Board, Player, Depth, Value)) ).

% -- pilih langkah terbaik (API lama, tetap dipertahankan) --
%    default: style balanced, tanpa opening book
best_move(Board, Player, Depth, BestCol) :-
    best_move_styled(Board, Player, Depth, balanced, BestCol).

% -- pilih langkah terbaik dengan gaya (personality) tertentu --
best_move_styled(Board, Player, Depth, Style, BestCol) :-
    reset_search_stats,
    retractall(tt_entry(_,_,_,_)),
    ordered_moves(Board, Moves),
    Moves \== [],
    Cfg = cfg(Player, Style),
    score_moves(Moves, Board, Player, Depth, Cfg, Scored),
    max_pair(Scored, _-BestCol),
    !.

% skor tiap langkah teratas (REKURENS + LIST pasangan Skor-Kolom)
score_moves([], _, _, _, _, []).
score_moves([Col|Rest], Board, Player, Depth, Cfg, [Score-Col|More]) :-
    drop(Board, Col, Player, Child),
    ( won(Child, Player) ->
        Score is 1000000 + Depth              % menang langsung
    ; other(Player, Opp), D1 is Depth - 1,
      negamax(Child, Opp, D1, -10000000, 10000000, Cfg, OppVal),
      Score is -OppVal
    ),
    score_moves(Rest, Board, Player, Depth, Cfg, More).

% ambil pasangan Skor-Kolom dengan skor tertinggi (REKURENS)
max_pair([P], P) :- !.
max_pair([S1-C1|Rest], Best) :-
    Rest = [_|_],
    max_pair(Rest, S2-C2),
    ( S1 >= S2 -> Best = S1-C1 ; Best = S2-C2 ),
    !.

% -- negamax dengan alpha-beta + TT + statistik --
%    Cfg = cfg(RootPlayer, Style)
%    RootPlayer dipakai HANYA utk mengklasifikasi cutoff (lihat
%    nm_loop) -- ini kesetaraan negamax<->minimax standar: node
%    dengan Player == RootPlayer setara node MAX pada pohon
%    klasik (cutoff-nya = Beta Cutoff), node dengan Player lawan
%    setara node MIN (cutoff-nya = Alpha Cutoff).
negamax(Board, Player, Depth, Alpha, Beta, Cfg, Value) :-
    bump_counter(nodes),
    ( tt_entry(Board, Player, Depth, Value) ->
        bump_counter(tt_hit)
    ; bump_counter(tt_miss),
      compute_negamax(Board, Player, Depth, Alpha, Beta, Cfg, Value)
    ).

compute_negamax(Board, Player, Depth, _Alpha, _Beta, Cfg, Value) :-
    Depth =< 0, !,
    Cfg = cfg(_, Style),
    heuristic(Board, Player, Style, Value),
    tt_store(Board, Player, Depth, Value).
compute_negamax(Board, Player, Depth, Alpha, Beta, Cfg, Value) :-
    ordered_moves(Board, Moves),
    ( Moves == [] ->
        Cfg = cfg(_, Style),
        heuristic(Board, Player, Style, Value),
        tt_store(Board, Player, Depth, Value)
    ; nm_loop(Moves, Board, Player, Depth, Alpha, Beta, Cfg, -10000000, Value, Exact),
      ( Exact == yes -> tt_store(Board, Player, Depth, Value) ; true )
    ).

% loop langkah dengan pemangkasan alpha-beta (REKURENS)
% Exact = yes bila loop selesai penuh (nilai pasti, aman di-cache)
%         no  bila berhenti karena cutoff (nilai hanya bound)
nm_loop([], _, _, _, _, _, _, Best, Best, yes).
nm_loop([Col|Rest], Board, Player, Depth, Alpha, Beta, Cfg, Acc, Value, Exact) :-
    drop(Board, Col, Player, Child),
    ( won(Child, Player) ->
        Score is 1000000 + Depth              % menang lebih cepat = lebih baik
    ; other(Player, Opp), D1 is Depth - 1,
      NA is -Beta, NB is -Alpha,
      negamax(Child, Opp, D1, NA, NB, Cfg, OppVal),
      Score is -OppVal
    ),
    ( Score > Acc -> Acc1 = Score ; Acc1 = Acc ),
    ( Alpha > Acc1 -> Alpha1 = Alpha ; Alpha1 = Acc1 ),
    ( Alpha1 >= Beta ->
        Value = Acc1, Exact = no,
        Cfg = cfg(RootPlayer, _),
        ( Player == RootPlayer -> bump_counter(beta_cut) ; bump_counter(alpha_cut) ),
        !                                     % beta cutoff (CUT eksplisit)
    ; nm_loop(Rest, Board, Player, Depth, Alpha1, Beta, Cfg, Acc1, Value, Exact)
    ).

% ============================================================
%  Heuristik: skor papan dari sudut pandang Player, dipengaruhi
%  Style (personality AI - lihat bagian Personality di bawah)
% ============================================================
heuristic(Board, Player, Style, Value) :-
    other(Player, Opp),
    all_windows(Board, Ws),
    sum_windows(Ws, Player, Opp, Style, 0, Value).

all_windows(Board, Windows) :-
    findall(Cells,
        ( between(1,7,C), between(1,6,R),
          member((DC,DR), [(1,0),(0,1),(1,1),(1,-1)]),
          window_cells(Board, C, R, DC, DR, Cells) ),
        Windows).

window_cells(Board, C, R, DC, DR, [V0,V1,V2,V3]) :-
    cell(Board, C, R, V0),
    C1 is C+DC,   R1 is R+DR,   cell(Board, C1, R1, V1),
    C2 is C+2*DC, R2 is R+2*DR, cell(Board, C2, R2, V2),
    C3 is C+3*DC, R3 is R+3*DR, cell(Board, C3, R3, V3).

sum_windows([], _, _, _, Acc, Acc).
sum_windows([W|Rest], P, O, Style, Acc, Value) :-
    window_score(W, P, O, Style, S),
    Acc1 is Acc + S,
    sum_windows(Rest, P, O, Style, Acc1, Value).

window_score(W, P, O, Style, S) :-
    count(W, P, CP), count(W, O, CO),
    ( CP > 0, CO > 0 -> S = 0                % jendela terhalang dua warna
    ; CP > 0        -> style_score(Style, self, CP, S)
    ; CO > 0        -> style_score(Style, opp, CO, S0), S is -S0
    ;                  S = 0
    ).

base_score(1, 1).
base_score(2, 10).
base_score(3, 50).
base_score(4, 10000).

style_score(Style, Side, N, S) :-
    base_score(N, B),
    style_mult(Style, Side, Num, Den),
    S is (B * Num) // Den.

% -- tabel gaya bermain AI (Personality) --
%    aggressive : bobot menyerang (bidak sendiri) dinaikkan
%    defensive  : bobot bertahan (blokir bidak lawan) dinaikkan
%    balanced   : bobot standar kedua sisi
%    random     : tidak dipakai langsung (lihat best_move_random),
%                 tapi didefinisikan lengkap agar heuristic tak
%                 pernah gagal bila style ini terlanjur terpanggil.
style_mult(balanced,   self, 1, 1).
style_mult(balanced,   opp,  1, 1).
style_mult(aggressive, self, 3, 2).
style_mult(aggressive, opp,  1, 1).
style_mult(defensive,  self, 1, 1).
style_mult(defensive,  opp,  3, 2).
style_mult(random,     self, 1, 1).
style_mult(random,     opp,  1, 1).

count([], _, 0).
count([X|T], X, N) :- !, count(T, X, N0), N is N0 + 1.
count([_|T], X, N) :- count(T, X, N).

% ============================================================
%  Format angka dengan pemisah ribuan: 18245 -> '18,245'
% ============================================================
format_thousands(N, Atom) :-
    number_codes(N, Codes),
    reverse(Codes, Rev),
    group3(Rev, Grouped),
    reverse(Grouped, Final),
    atom_codes(Atom, Final).

group3([A,B,C,D|Rest], Out) :- !,
    group3([D|Rest], Out1),
    append([A,B,C,0',], [], Sep),   % sisipkan koma setelah 3 digit
    append(Sep, Out1, Out).
group3(Digits, Digits).

% -- cetak statistik pencarian AI (dipanggil setelah best_move_styled) --
print_search_stats(Depth, TimeMs) :-
    get_counter(nodes, Nodes),
    get_counter(alpha_cut, ACut),
    get_counter(beta_cut, BCut),
    format_thousands(Nodes, NodesFmt),
    format_thousands(ACut, ACutFmt),
    format_thousands(BCut, BCutFmt),
    TimeSec is TimeMs / 1000.0,
    nl,
    format("  Depth        : ~w~n", [Depth]),
    format("  Nodes        : ~w~n", [NodesFmt]),
    format("  Alpha Cutoff : ~w~n", [ACutFmt]),
    format("  Beta Cutoff  : ~w~n", [BCutFmt]),
    format("  Time         : ~2f sec~n", [TimeSec]), nl.

% ============================================================
%  Analisis langkah: kemenangan instan, ancaman, top-N, hint
% ============================================================
immediate_win(Board, Player, Col) :-
    valid_move(Board, Col),
    drop(Board, Col, Player, NB),
    won(NB, Player).

opponent_threats(Board, Player, Cols) :-
    other(Player, Opp),
    findall(C, immediate_win(Board, Opp, C), Cols).

% semua langkah terurut skor menurun (style balanced -> "objektif")
top_moves(Board, Player, Depth, Sorted) :-
    ordered_moves(Board, Moves),
    Cfg = cfg(Player, balanced),
    score_moves(Moves, Board, Player, Depth, Cfg, Scored),
    keysort(Scored, Asc),
    reverse(Asc, Sorted).

% ============================================================
%  Mode MUDAH: pilih acak di antara langkah mendekati-terbaik
% ============================================================
best_move_easy(Board, Player, Depth, Col) :-
    top_moves(Board, Player, Depth, Sorted),
    Sorted = [BestS-_|_],
    Margin = 40,
    Thresh is BestS - Margin,
    findall(C, ( member(S-C, Sorted), S >= Thresh ), Cands),
    length(Cands, N),
    next_rand(N, R),
    I is R + 1,
    nth1(I, Cands, Col).

% ============================================================
%  Mode RANDOM (personality): tetap kompeten pada kondisi
%  taktis (ambil menang / blokir ancaman tunggal), selain itu
%  benar-benar acak. Tidak memanggil minimax sama sekali.
% ============================================================
best_move_random(Board, Player, Col) :-
    ( immediate_win(Board, Player, Col) -> true
    ; opponent_threats(Board, Player, Threats), Threats \== [] ->
        length(Threats, NT), next_rand(NT, R), I is R+1, nth1(I, Threats, Col)
    ; ordered_moves(Board, Moves),
      length(Moves, NM), next_rand(NM, R2), I2 is R2+1, nth1(I2, Moves, Col)
    ), !.

% ---- PRNG sederhana (LCG) dengan seed dinamis (dependency-free) ----
rng_set(S) :- retractall(rng_seed(_)), assertz(rng_seed(S)).

next_rand(N, R) :-
    ( retract(rng_seed(S0)) -> true ; S0 = 2463534242 ),
    S is (S0 * 1103515245 + 12345) /\ 2147483647,
    assertz(rng_seed(S)),
    R is S mod N.

% ============================================================
%  Pemilihan langkah menurut tingkat kesulitan + personality.
%  choose_move/5      : jalur lama (kompatibel: level saja)
%  choose_move_full/6 : level + style personality
% ============================================================
choose_move(mudah, Board, Player, Depth, Col) :- !,
    best_move_easy(Board, Player, Depth, Col).
choose_move(expert, Board, Player, Depth, Col) :- !,
    book_or_search(balanced, Board, Player, Depth, Col).
choose_move(_Level, Board, Player, Depth, Col) :-
    best_move(Board, Player, Depth, Col).

choose_move_full(_Level, random, Board, Player, _Depth, Col) :- !,
    best_move_random(Board, Player, Col).
choose_move_full(mudah, _Style, Board, Player, Depth, Col) :- !,
    best_move_easy(Board, Player, Depth, Col).
choose_move_full(expert, Style, Board, Player, Depth, Col) :- !,
    book_or_search(Style, Board, Player, Depth, Col).
choose_move_full(_Level, Style, Board, Player, Depth, Col) :-
    book_or_search(Style, Board, Player, Depth, Col).

% ============================================================
%  Opening Book (ilustratif)
%  CATATAN JUJUR: ini BUKAN basis data solved-game Connect Four
%  yang lengkap (itu perlu jutaan posisi hasil perfect-play
%  search). Ini beberapa entri representatif untuk 1-2 langkah
%  pembuka yang mendemonstrasikan MEKANISME opening book: AI
%  mengecek buku dulu sebelum memanggil minimax.
% ============================================================
setup_opening_book :-
    retractall(book_move_fact(_,_)),
    assertz(book_move_fact([], 4)),
    assertz(book_move_fact([4], 3)),
    assertz(book_move_fact([4,3], 5)),
    assertz(book_move_fact([4,4], 3)),
    assertz(book_move_fact([1], 4)),
    assertz(book_move_fact([7], 4)),
    assertz(book_move_fact([2], 4)),
    assertz(book_move_fact([6], 4)).

:- initialization(setup_opening_book).

book_or_search(Style, Board, Player, Depth, Col) :-
    ( move_log(L), book_move_fact(L, BookCol), valid_move(Board, BookCol) ->
        Col = BookCol
    ; best_move_styled(Board, Player, Depth, Style, Col)
    ).

% ============================================================
%  Zobrist Hash (demonstrasi teknik hashing posisi papan)
%  Tabel acak dibangun SEKALI saat program dimuat. Setiap sel
%  terisi (Col,Row,Piece) punya nilai acak; hash papan = XOR
%  seluruh nilai sel yang terisi. Dua papan identik selalu
%  menghasilkan hash sama; papan berbeda HAMPIR PASTI berbeda.
%  CATATAN: Transposition Table proyek ini tetap memakai
%  representasi papan (list) sebagai kunci -- bebas collision
%  sepenuhnya. Zobrist hash didemonstrasikan terpisah sebagai
%  identitas posisi; pada engine performa-tinggi (representasi
%  papan berupa bitboard), hash inilah yang lazim dipakai
%  sebagai kunci TT agar lookup jauh lebih cepat.
% ============================================================
setup_zobrist :-
    retractall(zobrist_val(_,_,_,_)),
    rng_set(1337),
    forall(
        ( between(1,7,C), between(1,6,R), member(P,[x,o]) ),
        ( next_rand(1073741823, R1), next_rand(1073741823, R2),
          V is xor(R1 << 28, R2),          % ~58 bit -- aman (GNU Prolog
          assertz(zobrist_val(C,R,P,V)) )  % integer asli TANPA bignum,
    ),                                     % wrap diam-diam mulai ~2^60
    rng_set(2463534242).           % kembalikan seed default utk gameplay

:- initialization(setup_zobrist).

zobrist_hash(Board, Hash) :-
    findall(V,
        ( between(1,7,C), between(1,6,R), cell(Board,C,R,P),
          ( P == x ; P == o ),
          zobrist_val(C,R,P,V) ),
        Vals),
    fold_xor(Vals, 0, Hash).

fold_xor([], Acc, Acc).
fold_xor([V|T], Acc, R) :- Acc1 is xor(Acc, V), fold_xor(T, Acc1, R).

% ============================================================
%  Principal Variation: garis terbaik hasil pencarian (perkiraan
%  via pemanggilan best_move berulang pada kedalaman menurun).
%  CATATAN JUJUR: ini APROKSIMASI, bukan PV murni yang disimpan
%  langsung dari satu pencarian negamax (yang butuh menyimpan
%  rantai langkah terbaik di tiap node -- perubahan lebih invasif
%  ke inti negamax). Pada style balanced (deterministik) garis
%  hasil pemanggilan berulang ini pada praktiknya konsisten.
% ============================================================
principal_variation(Board, Player, Depth, Eval, PVList) :-
    top_moves(Board, Player, Depth, [BestScore-BestCol|_]),
    Eval = BestScore,
    drop(Board, BestCol, Player, NB),
    other(Player, Opp), D1 is Depth - 1,
    ( won(NB, Player) -> PVList = [Player-BestCol]
    ; terminal_like(NB) -> PVList = [Player-BestCol]
    ; D1 =< 0 -> PVList = [Player-BestCol]
    ; pv_continue(NB, Opp, D1, Rest), PVList = [Player-BestCol|Rest]
    ).

pv_continue(Board, Player, Depth, PVList) :-
    ( Depth =< 0 -> PVList = []
    ; terminal_like(Board) -> PVList = []
    ; best_move(Board, Player, Depth, Col) ->
        drop(Board, Col, Player, NB),
        other(Player, Opp), D1 is Depth - 1,
        ( won(NB, Player) -> PVList = [Player-Col]
        ; pv_continue(NB, Opp, D1, Rest), PVList = [Player-Col | Rest] )
    ; PVList = []
    ).

%  features.pl - fitur analisis & mode tambahan
%  Explainable AI, Position Analysis, Heat Map, Complexity
%  Analysis, Search Tree Visualization, Tournament, Benchmark,
%  Puzzle Mode.
% ============================================================

sum_ints([], 0).
sum_ints([X|T], S) :- sum_ints(T, S0), S is S0 + X.

% cetak angka dengan tanda + di depan bila >= 0 (GNU Prolog tidak
% mendukung format(atom(A),...), jadi cetak langsung ke stream)
print_signed(N) :- N >= 0, !, format("+~w", [N]).
print_signed(N) :- format("~w", [N]).

% ============================================================
%  Position Analysis (dipakai juga oleh Explainable AI)
% ============================================================
center_weight(1,0). center_weight(2,1). center_weight(3,2).
center_weight(4,3). center_weight(5,2). center_weight(6,1). center_weight(7,0).

center_control(Board, Player, Score) :-
    findall(W, ( between(1,7,C), between(1,6,R), cell(Board,C,R,Player),
                 center_weight(C,W) ), Ws),
    sum_ints(Ws, Score).

count_open_windows(Board, Player, N, Count) :-
    other(Player, Opp),
    all_windows(Board, Ws),
    findall(1, ( member(W,Ws), count(W,Player,CP), count(W,Opp,CO),
                 CP =:= N, CO =:= 0 ), Matches),
    length(Matches, Count).

threat_score(Board, Player, Score) :-
    findall(C, immediate_win(Board,Player,C), Wins),
    length(Wins, N), Score is N * 25.

opp_threat_score(Board, Player, Score) :-
    opponent_threats(Board, Player, Threats),
    length(Threats, N), Score is -(N * 25).

position_breakdown(Board, Player, bd(Center,Threat,C2,C3,OppThreat,Total)) :-
    center_control(Board, Player, Center),
    threat_score(Board, Player, Threat),
    count_open_windows(Board, Player, 2, C2),
    count_open_windows(Board, Player, 3, C3),
    opp_threat_score(Board, Player, OppThreat),
    heuristic(Board, Player, balanced, Total).

print_position_analysis(Board, Player) :-
    position_breakdown(Board, Player, bd(Center,Threat,C2,C3,OppThreat,Total)),
    nl, write('  Position Analysis'), nl, nl,
    write('  Center Control  : '), print_signed(Center), nl,
    write('  Threat          : '), print_signed(Threat), nl,
    format("  Connect-2       : ~w~n", [C2]),
    format("  Connect-3       : ~w~n", [C3]),
    write('  Opponent Threat : '), print_signed(OppThreat), nl, nl,
    write('  Total Score     : '), print_signed(Total), nl, nl.

% ============================================================
%  Explainable AI
% ============================================================
explain_move(Board, Player, Col, Reasons) :-
    findall(R, applicable_reason(Board, Player, Col, R), Reasons0),
    ( Reasons0 == [] -> Reasons = ['Skor evaluasi terbaik pada kedalaman pencarian ini']
    ; Reasons = Reasons0 ).

applicable_reason(_Board, _Player, Col, 'Mengontrol center') :-
    member(Col, [3,4,5]).
applicable_reason(Board, Player, Col, 'Memblokir ancaman lawan') :-
    opponent_threats(Board, Player, Threats), member(Col, Threats).
applicable_reason(Board, Player, Col, 'Membentuk Connect-3 (peluang menang)') :-
    count_open_windows(Board, Player, 3, N3Before),
    drop(Board, Col, Player, NB),
    count_open_windows(NB, Player, 3, N3After),
    N3After > N3Before.
applicable_reason(Board, Player, Col, 'Membuka lebih dari satu peluang kemenangan (fork)') :-
    drop(Board, Col, Player, NB),
    findall(C, immediate_win(NB, Player, C), Wins),
    length(Wins, K), K >= 2.

print_explanation(Board, Player, Col, Score) :-
    explain_move(Board, Player, Col, Reasons),
    nl, format("  AI memilih kolom ~w~n~n", [Col]),
    write('  Alasan:'), nl,
    print_reasons(Reasons),
    nl, write('  Evaluation Score : '), print_signed(Score), nl, nl.

print_reasons([]).
print_reasons([R|Rest]) :- format("  - ~w~n", [R]), print_reasons(Rest).

% ============================================================
%  Heat Map Evaluasi Kolom
% ============================================================
print_heatmap(Board, Player, Depth) :-
    top_moves(Board, Player, Depth, Sorted),
    Sorted = [_-BestCol|_],
    nl, write('  Heat Map Evaluasi Kolom'), nl, nl,
    print_heatmap_cols(1, Sorted, BestCol),
    nl.

print_heatmap_cols(8, _, _) :- !.
print_heatmap_cols(C, Sorted, BestCol) :-
    C =< 7,
    ( member(S-C, Sorted) -> true ; S = 0 ),
    ( C == BestCol -> Mark = '  *' ; Mark = '' ),
    write('  Column '), write(C), write(' : '), print_signed(S), write(Mark), nl,
    C1 is C + 1,
    print_heatmap_cols(C1, Sorted, BestCol).

% ============================================================
%  Smart Hint: peringatan sebelum langkah buruk
% ============================================================
move_is_risky(Board, Player, Col) :-
    valid_move(Board, Col),
    drop(Board, Col, Player, NB),
    other(Player, Opp),
    immediate_win(NB, Opp, _).

% ============================================================
%  Analisis Kompleksitas (memakai statistik pencarian TERAKHIR)
% ============================================================
complexity_analysis(Board, Depth) :-
    ordered_moves(Board, Moves), length(Moves, BF),
    ( BF > 0 -> Est is BF ^ Depth ; Est = 0 ),
    get_counter(nodes, Visited),
    ( Est > 0 -> PruneEff is 100 - (Visited * 100 // Est) ; PruneEff = 0 ),
    format_thousands(Est, EstFmt),
    format_thousands(Visited, VisFmt),
    nl, write('  Analisis Kompleksitas'), nl, nl,
    format("  Current Branching Factor : ~w~n", [BF]),
    format("  Estimated Nodes          : ~w~n", [EstFmt]),
    format("  Visited Nodes            : ~w~n", [VisFmt]),
    format("  Pruning Efficiency       : ~w", [PruneEff]), write('%'), nl, nl.

% ============================================================
%  Search Tree Visualization (2 ply, alpha-beta NYATA agar
%  cutoff yang ditampilkan genuine -- bukan pohon exhaustive
%  yang dipoles seolah-olah dipangkas)
% ============================================================
trace_tree(Board, Player) :-
    nl, write('Depth 0'), nl,
    ordered_moves(Board, Moves),
    length(Moves, NM),
    trace_root(Moves, Board, Player, 1, NM, -10000000, 10000000).

trace_root([], _, _, _, _, _, _).
trace_root([Col|Rest], Board, Player, Idx, Total, Alpha, Beta) :-
    ( Idx == Total -> Branch = '`-- ', ChildPrefix = '    ' ; Branch = '|-- ', ChildPrefix = '|   ' ),
    format("~wColumn ~w~n", [Branch, Col]),
    drop(Board, Col, Player, Child),
    ( won(Child, Player) ->
        format("~w`-- Menang!~n", [ChildPrefix]), Val = 1000000
    ; other(Player, Opp),
      NA is -Beta, NB is -Alpha,
      trace_level2(Child, Opp, ChildPrefix, NA, NB, NegVal),
      Val is -NegVal
    ),
    ( Val > Alpha -> Alpha1 = Val ; Alpha1 = Alpha ),
    Idx1 is Idx + 1,
    trace_root(Rest, Board, Player, Idx1, Total, Alpha1, Beta).

trace_level2(Board, Player, Prefix, Alpha, Beta, Value) :-
    ordered_moves(Board, Moves),
    length(Moves, NM),
    ( NM == 0 -> heuristic(Board, Player, balanced, Value)
    ; trace_level2_loop(Moves, Board, Player, 1, NM, Prefix, Alpha, Beta, -10000000, Value)
    ).

trace_level2_loop([], _, _, _, _, _, _, _, Best, Best).
trace_level2_loop([Col|Rest], Board, Player, Idx, Total, Prefix, Alpha, Beta, Acc, Value) :-
    ( Idx == Total -> Branch = '`-- ' ; Branch = '|-- ' ),
    drop(Board, Col, Player, Child),
    ( won(Child, Player) ->
        Score = 1000000,
        format("~w~wScore = MENANG(lawan)~n", [Prefix, Branch])
    ; heuristic(Child, Player, balanced, Score0), Score = Score0,
      format("~w~wScore = ~w~n", [Prefix, Branch, Score])
    ),
    ( Score > Acc -> Acc1 = Score ; Acc1 = Acc ),
    ( Alpha > Acc1 -> Alpha1 = Alpha ; Alpha1 = Acc1 ),
    ( Alpha1 >= Beta ->
        format("~w    (Beta Cutoff - sisa kolom dipangkas)~n", [Prefix]),
        Value = Acc1
    ; Idx1 is Idx + 1,
      trace_level2_loop(Rest, Board, Player, Idx1, Total, Prefix, Alpha1, Beta, Acc1, Value)
    ).

% ============================================================
%  Benchmark AI
% ============================================================
run_benchmark(MaxDepth) :-
    nl, write('  Depth    Nodes         Time'), nl, nl,
    initial_board(B),
    benchmark_loop(1, MaxDepth, B).

benchmark_loop(D, Max, _) :- D > Max, !.
benchmark_loop(D, Max, Board) :-
    statistics(cpu_time,[T0|_]),
    best_move(Board, x, D, _),
    statistics(cpu_time,[T1|_]),
    Dt is T1 - T0,
    get_counter(nodes, Nodes),
    format_thousands(Nodes, NF),
    TimeSec is Dt / 1000.0,
    format("  ~w        ~w      ~2f s~n", [D, NF, TimeSec]),
    D1 is D + 1,
    benchmark_loop(D1, Max, Board).

% ============================================================
%  AI vs AI Tournament (failure-driven, konsisten dgn desain
%  proyek: hindari rekursi maju panjang yang tak mereklaim
%  global stack)
% ============================================================
:- dynamic(tourn_result/2).
:- dynamic(tourn_progress/1).
:- dynamic(match_state/2).

tourn_reset :-
    retractall(tourn_result(_,_)),
    assertz(tourn_result(awin,0)), assertz(tourn_result(bwin,0)), assertz(tourn_result(draw,0)).

tourn_bump(K) :-
    ( retract(tourn_result(K,N)) -> N1 is N + 1 ; N1 = 1 ),
    assertz(tourn_result(K,N1)).

run_tournament(DepthA, DepthB, N) :-
    format("~n  Tournament~n~n  AI Depth ~w~n  VS~n  AI Depth ~w~n~n  Match : ~w~n~n", [DepthA,DepthB,N]),
    tourn_reset,
    retractall(tourn_progress(_)), assertz(tourn_progress(1)),
    ( repeat,
        tourn_progress(I),
        ( I > N -> !
        ; ( 0 is I mod 2 -> play_one_match(DepthB, DepthA, ResultRaw), swap_result(ResultRaw, Result)
          ; play_one_match(DepthA, DepthB, Result)
          ),
          ( Result == a -> tourn_bump(awin)
          ; Result == b -> tourn_bump(bwin)
          ; tourn_bump(draw) ),
          I1 is I + 1,
          retractall(tourn_progress(_)), assertz(tourn_progress(I1)),
          fail
        )
    ),
    tourn_report(DepthA, DepthB).

% pada match bernomor genap, config A & B ditukar posisi (A=O, B=X)
% agar tak ada bias keuntungan-jalan-duluan; hasil ditukar balik
% supaya tourn_result tetap konsisten milik A/B, bukan X/O.
swap_result(a, b).
swap_result(b, a).
swap_result(draw, draw).

% -- satu pertandingan penuh, memakai pemilihan "mendekati-terbaik"
%    (best_move_easy, margin kecil) agar antar match tidak selalu
%    identik walau kedalaman sama -- deterministic best_move murni
%    akan menghasilkan game yang SAMA PERSIS tiap match sehingga
%    statistik turnamen tidak informatif.
play_one_match(DepthA, DepthB, Result) :-
    initial_board(B),
    retractall(match_state(_,_)), assertz(match_state(B, x)),
    ( repeat,
        match_state(Bd, T),
        ( won(Bd, x) -> !, Result = a
        ; won(Bd, o) -> !, Result = b
        ; board_full(Bd) -> !, Result = draw
        ; ( T == x -> best_move_easy(Bd, x, DepthA, Col) ; best_move_easy(Bd, o, DepthB, Col) ),
          drop(Bd, Col, T, NB),
          other(T, Next),
          retractall(match_state(_,_)), assertz(match_state(NB, Next)),
          fail
        )
    ).

tourn_report(DepthA, DepthB) :-
    tourn_result(awin,AW), tourn_result(bwin,BW), tourn_result(draw,DR),
    nl,
    format("  Depth ~w Win : ~w~n", [DepthA, AW]),
    format("  Depth ~w Win : ~w~n", [DepthB, BW]),
    format("  Draw : ~w~n", [DR]), nl.

% ============================================================
%  Puzzle Mode (setiap puzzle diverifikasi PROGRAMATIK, bukan
%  jawaban hardcode -- benar jika kolom = kemenangan instan ATAU
%  kolom = blokir ancaman lawan)
% ============================================================
setup_puzzles :-
    retractall(puzzle_fact(_,_,_,_)),
    initial_board(E),
    drop(E,1,x,P1a), drop(P1a,2,x,P1b), drop(P1b,3,x,P1c),
    assertz(puzzle_fact(1, P1c, x, 'Giliran X. Temukan langkah kemenangan.')),
    drop(E,5,x,P2a), drop(P2a,5,x,P2b), drop(P2b,5,x,P2c),
    assertz(puzzle_fact(2, P2c, o, 'Giliran O. X mengancam menang. Temukan langkah blokir.')),
    drop(E,1,x,Q1), drop(Q1,2,o,Q2), drop(Q2,2,x,Q3), drop(Q3,3,o,Q4),
    drop(Q4,3,o,Q5), drop(Q5,3,x,Q6), drop(Q6,4,o,Q7), drop(Q7,4,o,Q8), drop(Q8,4,o,Q9),
    assertz(puzzle_fact(3, Q9, x, 'Giliran X. Temukan langkah kemenangan (diagonal).')),
    drop(E,6,o,R1), drop(R1,6,o,R2), drop(R2,6,o,R3),
    assertz(puzzle_fact(4, R3, o, 'Giliran O. Temukan langkah kemenangan.')),
    drop(E,1,o,S1), drop(S1,2,o,S2), drop(S2,3,o,S3),
    assertz(puzzle_fact(5, S3, x, 'Giliran X. O mengancam menang. Temukan langkah blokir.')).

:- initialization(setup_puzzles).

check_puzzle_answer(Board, Turn, Col, correct) :-
    immediate_win(Board, Turn, Col), !.
check_puzzle_answer(Board, Turn, Col, correct) :-
    opponent_threats(Board, Turn, Threats),
    Threats \== [], member(Col, Threats), !.
check_puzzle_answer(_, _, _, incorrect).

puzzle_solution_hint(Board, Turn, Col) :-
    ( immediate_win(Board, Turn, Col) -> true
    ; opponent_threats(Board, Turn, Threats), Threats = [Col|_] ).

% ============================================================
%  io.pl - antarmuka lengkap: mode, kesulitan, personality,
%          undo/redo tak terbatas, hint, smart hint, peringatan
%          ancaman, save/load, replay interaktif+export,
%          statistik, benchmark, tournament, puzzle mode,
%          explainable AI, position analysis, heat map,
%          complexity analysis, search tree viz, zobrist, PV.
%  Konsep: LOOP (repeat/between + fail), FAIL (tolak langkah
%          ilegal + undo/redo + reclaim stack), FILE PROCESSING
%          (save/load state, move-log, statistik, export replay).
% ============================================================

:- dynamic(ai_last_move/3).    % ai_last_move(BoardSebelum, Player, Col) - utk explain.

% ---- nama & simbol ----
piece_name(x, 'X').
piece_name(o, 'O').
symbol(e, '.').
symbol(x, 'X').
symbol(o, 'O').

% ============================================================
%  Tampilan papan
% ============================================================
filled_in_col([], 0).
filled_in_col([e|_], 0) :- !.
filled_in_col([X|T], N) :- X \== e, filled_in_col(T, N0), N is N0 + 1.

filled(Board, K) :- filled(Board, 0, K).
filled([], A, A).
filled([Col|Rest], A, K) :- filled_in_col(Col, N), A1 is A + N, filled(Rest, A1, K).

display_state(Board, Turn) :-
    filled(Board, K), MoveNo is K + 1,
    piece_name(Turn, Nm),
    nl,
    format("  Langkah ke-~w   |   Giliran: ~w~n", [MoveNo, Nm]),
    print_board(Board).

print_board(Board) :-
    ( between(1, 6, FromTop),
      Row is 7 - FromTop,
      print_row(Board, Row),
      fail
    ; true ),
    write('  ---------------'), nl,
    write('   1 2 3 4 5 6 7'), nl,
    print_marker, nl.

print_row(Board, Row) :-
    write('  | '),
    ( between(1, 7, Col),
      cell(Board, Col, Row, V),
      symbol(V, S),
      write(S), write(' '),
      fail
    ; true ),
    write('|'), nl.

print_marker :-
    ( last_pos(Col), integer(Col) ->
        Pad is 3 + 2*(Col-1),
        tab(Pad), write('^'), write(' (terakhir)'), nl
    ; true ).

set_last(Col) :- retractall(last_pos(_)), assertz(last_pos(Col)).
clear_last :- retractall(last_pos(_)).

% ============================================================
%  FILE PROCESSING
% ============================================================
save_game(Board, Player, Depth, File) :-
    open(File, write, S),
    writeq(S, game(Board, Player, Depth)), write(S, '.'), nl(S),
    close(S).

load_game(Board, Player, Depth, File) :-
    catch(( open(File, read, S),
            read(S, game(Board, Player, Depth)),
            close(S) ), _E, fail).

save_log(File) :-
    move_log(L),
    open(File, write, S),
    writeq(S, movelog(L)), write(S, '.'), nl(S),
    close(S).

load_log(L, File) :-
    catch(( open(File, read, S),
            read(S, movelog(L)),
            close(S) ), _E, fail).

stats_file('stats.txt').

load_stats :-
    retractall(stat(_,_)),
    stats_file(F),
    ( catch(( open(F, read, S), read(S, stats(X,O,D)), close(S) ), _E, fail)
    -> assertz(stat(xwin,X)), assertz(stat(owin,O)), assertz(stat(draw,D))
    ;  assertz(stat(xwin,0)), assertz(stat(owin,0)), assertz(stat(draw,0)) ).

save_stats :-
    stat(xwin,X), stat(owin,O), stat(draw,D),
    stats_file(F),
    open(F, write, S),
    writeq(S, stats(X,O,D)), write(S, '.'), nl(S),
    close(S).

bump(Key) :-
    ( retract(stat(Key,N)) -> N1 is N + 1 ; N1 = 1 ),
    assertz(stat(Key,N1)).

show_stats :-
    ( stat(xwin,_) -> true ; load_stats ),
    stat(xwin,X), stat(owin,O), stat(draw,D),
    Total is X + O + D,
    nl, write('===== STATISTIK ====='), nl,
    format("  Menang X : ~w~n", [X]),
    format("  Menang O : ~w~n", [O]),
    format("  Seri     : ~w~n", [D]),
    format("  Total    : ~w~n", [Total]),
    write('====================='), nl, nl.

% ============================================================
%  Adaptive AI: saran (bukan paksaan) berbasis riwayat menang/kalah
% ============================================================
adaptive_suggestion :-
    ( stat(xwin,_) -> true ; load_stats ),
    stat(xwin,X), stat(owin,O),
    Total is X + O,
    ( Total < 3 -> true
    ; WinRate is X * 100 // Total,
      ( WinRate >= 65 ->
          format("~n  >> Adaptive AI: kamu menang ~w", [WinRate]), write('%'),
          format(" dari ~w game terakhir vs AI.~n     Coba tingkat kesulitan lebih tinggi?~n", [Total])
      ; WinRate =< 35 ->
          LoseRate is 100 - WinRate,
          format("~n  >> Adaptive AI: AI menang ~w", [LoseRate]), write('%'),
          format(" dari ~w game terakhir.~n     Coba tingkat kesulitan lebih rendah?~n", [Total])
      ; true
      )
    ).

% ============================================================
%  Hint & peringatan ancaman
% ============================================================
do_hint(Board, Player, Depth) :-
    top_moves(Board, Player, Depth, Sorted),
    take(3, Sorted, Top3),
    write('  >> Analisis AI (3 kolom teratas):'), nl,
    print_hints(Top3),
    Sorted = [_-BestCol|_],
    format("  >> Rekomendasi: kolom ~w~n", [BestCol]).

print_hints([]).
print_hints([S-C|T]) :-
    ( S >= 1000000 -> Label = ' (MENANG!)'
    ; S =< -1000000 -> Label = ' (kalah)'
    ; Label = '' ),
    format("       kolom ~w : skor ~w~w~n", [C, S, Label]),
    print_hints(T).

maybe_warn(Board, Player) :-
    opponent_threats(Board, Player, Cols),
    ( Cols == [] -> true
    ; format("  !! Awas: lawan mengancam menang di kolom ~w~n", [Cols]) ).

% ============================================================
%  Riwayat langkah, undo & redo (snapshot 4-tuple: papan, giliran,
%  kedalaman, DAN move_log -- sehingga redo bisa memulihkan log
%  secara utuh, bukan cuma papan)
% ============================================================
record_move(Col) :-
    ( retract(move_log(L)) -> true ; L = [] ),
    append(L, [Col], L2),
    assertz(move_log(L2)).

take(0, _, []) :- !.
take(_, [], []) :- !.
take(N, [H|T], [H|R]) :- N > 0, N1 is N - 1, take(N1, T, R).

push_undo(S) :-
    ( retract(undo_stack(U)) -> true ; U = [] ),
    assertz(undo_stack([S|U])).

push_redo(S) :-
    ( retract(redo_stack(R)) -> true ; R = [] ),
    assertz(redo_stack([S|R])).

push_snapshot(B, T, D) :-
    ( move_log(L) -> true ; L = [] ),
    push_undo(s(B,T,D,L)).

clear_redo :- retractall(redo_stack(_)), assertz(redo_stack([])).

% undo: kembalikan ke snapshot giliran-manusia sebelumnya, simpan
% state yang ditinggalkan ke redo_stack agar bisa di-redo.
do_undo :-
    undo_stack([Cur, s(B,T,D,L) | More]),
    !,
    push_redo(Cur),
    set_state(B, T, D),
    retractall(move_log(_)), assertz(move_log(L)),
    retractall(undo_stack(_)), assertz(undo_stack(More)),
    clear_last.

% redo: pulihkan snapshot yang tadi di-undo, simpan state sekarang
% ke undo_stack agar rantai undo tetap konsisten.
do_redo :-
    redo_stack([s(B,T,D,L) | More]),
    !,
    game_state(CurB, CurT, CurD),
    ( move_log(CurL) -> true ; CurL = [] ),
    push_undo(s(CurB,CurT,CurD,CurL)),
    set_state(B, T, D),
    retractall(move_log(_)), assertz(move_log(L)),
    retractall(redo_stack(_)), assertz(redo_stack(More)),
    clear_last.

set_state(B, T, D) :-
    retractall(game_state(_,_,_)),
    assertz(game_state(B, T, D)).

% ============================================================
%  Loop permainan (failure-driven, generik untuk semua mode)
% ============================================================
start_game(XType, OType, Depth) :-
    initial_board(B),
    retractall(player_type(_,_)),
    assertz(player_type(x, XType)), assertz(player_type(o, OType)),
    retractall(undo_stack(_)), assertz(undo_stack([])),
    retractall(redo_stack(_)), assertz(redo_stack([])),
    retractall(move_log(_)), assertz(move_log([])),
    retractall(ai_last_move(_,_,_)),
    clear_last,
    set_state(B, x, Depth),
    ( catch(game_loop, quit_game, (write('  >> Kembali ke menu.'), nl)) -> true ; true ).

game_loop :-
    repeat,
        game_state(B, T, D),
        ( terminal(B)
        -> !, finish_game(B)
        ;  player_type(T, Type),
           take_turn(Type, B, T, D),
           fail
        ).

terminal(Board) :- ( won(Board, _) -> true ; board_full(Board) ).

take_turn(human, B, T, D) :- !,
    push_snapshot(B, T, D),
    display_state(B, T),
    maybe_warn(B, T),
    human_move(B, T, D, NB, Col),
    record_move(Col), set_last(Col),
    clear_redo,
    other(T, Next),
    set_state(NB, Next, D).
take_turn(ai, B, T, D) :-
    display_state(B, T),
    piece_name(T, Nm),
    format("  AI (~w) berpikir...~n", [Nm]),
    ( diff_level(Lvl) -> true ; Lvl = custom ),
    ( ai_style(Style) -> true ; Style = balanced ),
    statistics(cpu_time,[T0|_]),
    choose_move_full(Lvl, Style, B, T, D, Col),
    statistics(cpu_time,[T1|_]), TimeMs is T1 - T0,
    ( Style == random -> true ; print_search_stats(D, TimeMs) ),
    retractall(ai_last_move(_,_,_)), assertz(ai_last_move(B, T, Col)),
    format("  AI (~w) menjatuhkan bidak di kolom ~w~n", [Nm, Col]),
    drop(B, Col, T, NB),
    record_move(Col), set_last(Col),
    other(T, Next),
    set_state(NB, Next, D).

% ---- input manusia (rekursif; menangani semua command) ----
human_move(B, P, D, NB, Col) :-
    piece_name(P, Nm),
    format("  ~w, pilih kolom 1-7  (help. utk daftar perintah) : ", [Nm]),
    read(Input),
    dispatch(Input, B, P, D, NB, Col).

dispatch(quit, _, _, _, _, _) :- !, throw(quit_game).
dispatch(end_of_file, _, _, _, _, _) :- !, throw(quit_game).
dispatch(help, B, P, D, NB, Col) :- !, show_help, human_move(B, P, D, NB, Col).
dispatch(board, B, P, D, NB, Col) :- !, display_state(B, P), human_move(B, P, D, NB, Col).
dispatch(hint, B, P, D, NB, Col) :- !, do_hint(B, P, D), human_move(B, P, D, NB, Col).
dispatch(analysis, B, P, D, NB, Col) :- !, print_position_analysis(B, P), human_move(B, P, D, NB, Col).
dispatch(heatmap, B, P, D, NB, Col) :- !, print_heatmap(B, P, D), human_move(B, P, D, NB, Col).
dispatch(tree, B, P, D, NB, Col) :- !, trace_tree(B, P), human_move(B, P, D, NB, Col).
dispatch(zobrist, B, P, D, NB, Col) :- !,
    zobrist_hash(B, H), format("  Zobrist Hash posisi saat ini: ~w~n", [H]),
    human_move(B, P, D, NB, Col).
dispatch(pv, B, P, D, NB, Col) :- !,
    principal_variation(B, P, D, Eval, PV),
    print_pv(Eval, PV),
    human_move(B, P, D, NB, Col).
dispatch(complexity, B, P, D, NB, Col) :- !,
    best_move(B, P, D, _),
    complexity_analysis(B, D),
    human_move(B, P, D, NB, Col).
dispatch(explain, B, P, D, NB, Col) :- !,
    ( ai_last_move(LastBoard, LastPlayer, LastCol) ->
        drop(LastBoard, LastCol, LastPlayer, LastNB),
        heuristic(LastNB, LastPlayer, balanced, Score),
        print_explanation(LastBoard, LastPlayer, LastCol, Score)
    ; write('  >> Belum ada langkah AI untuk dijelaskan.'), nl
    ),
    human_move(B, P, D, NB, Col).
dispatch(save(F), B, P, D, NB, Col) :- !,
    ( save_game(B, P, D, F) -> format("  >> Disimpan ke ~w~n", [F]) ; write('  >> Gagal simpan.'), nl ),
    human_move(B, P, D, NB, Col).
dispatch(savelog(F), B, P, D, NB, Col) :- !,
    ( save_log(F) -> format("  >> Riwayat disimpan ke ~w~n", [F]) ; write('  >> Gagal.'), nl ),
    human_move(B, P, D, NB, Col).
dispatch(undo, B, P, D, NB, Col) :- !,
    ( do_undo -> fail
    ; write('  >> Tidak ada langkah untuk di-undo.'), nl, human_move(B, P, D, NB, Col) ).
dispatch(redo, B, P, D, NB, Col) :- !,
    ( do_redo -> fail
    ; write('  >> Tidak ada langkah untuk di-redo.'), nl, human_move(B, P, D, NB, Col) ).
dispatch(Col, B, P, D, NB, FinalCol) :-
    integer(Col), valid_move(B, Col), !,
    ( move_is_risky(B, P, Col) ->
        format("~n  Peringatan~n~n  Jika memilih kolom ~w, lawan bisa menang giliran berikutnya.~n~n  Lanjutkan? (y/n) : ", [Col]),
        read(Confirm),
        ( Confirm == y ->
            drop(B, Col, P, NB), FinalCol = Col
        ; write('  >> Dibatalkan, pilih kolom lain.'), nl,
          human_move(B, P, D, NB, FinalCol)
        )
    ; drop(B, Col, P, NB), FinalCol = Col
    ).
dispatch(Col, B, P, D, NB, C2) :-
    integer(Col), !,
    write('  >> Kolom penuh atau di luar 1-7.'), nl,
    human_move(B, P, D, NB, C2).
dispatch(_, B, P, D, NB, Col) :-
    write('  >> Perintah tak dikenal. Ketik help.'), nl,
    human_move(B, P, D, NB, Col).

print_pv(Eval, PV) :-
    nl, write('  Best Line'), nl, nl,
    print_pv_moves(PV),
    nl, write('  Evaluation : '), print_signed(Eval), nl, nl.

print_pv_moves([]).
print_pv_moves([Player-Col|Rest]) :-
    piece_name(Player, Nm),
    format("  ~w  :  ~w~n", [Nm, Col]),
    print_pv_moves(Rest).

show_help :-
    nl, write('  --- Perintah dalam permainan ---'), nl,
    write('    1..7             : jatuhkan bidak ke kolom'), nl,
    write('    hint.            : 3 kolom terbaik menurut AI'), nl,
    write('    analysis.        : position analysis (center/threat/connect)'), nl,
    write('    heatmap.         : heat map evaluasi tiap kolom'), nl,
    write('    tree.            : visualisasi search tree (2 ply)'), nl,
    write('    complexity.      : analisis kompleksitas pencarian'), nl,
    write('    pv.              : principal variation (best line)'), nl,
    write('    zobrist.         : tampilkan zobrist hash posisi ini'), nl,
    write('    explain.         : alasan langkah terakhir AI'), nl,
    write('    undo.  / redo.   : batalkan / ulangi langkah'), nl,
    write('    board.           : tampilkan papan lagi'), nl,
    write("    save('f.txt').   : simpan permainan"), nl,
    write("    savelog('f.txt').: simpan riwayat langkah"), nl,
    write('    quit.            : kembali ke menu'), nl, nl.

finish_game(Board) :-
    display_state(Board, x),
    ( won(Board, x) -> announce(x), bump(xwin)
    ; won(Board, o) -> announce(o), bump(owin)
    ; write('  === Papan penuh - SERI! ==='), nl, bump(draw) ),
    save_stats.

announce(P) :-
    piece_name(P, Nm),
    format("  === Pemain ~w MENANG! ===~n", [Nm]).

% ============================================================
%  Replay interaktif (next/prev/jump) + export (ascii/json)
% ============================================================
setup_replay(Moves) :-
    initial_board(B0),
    build_replay_boards(Moves, B0, x, [B0], BoardsRev),
    reverse(BoardsRev, Boards),
    retractall(replay_state(_,_,_)), assertz(replay_state(Boards, Moves, 0)).

build_replay_boards([], _, _, Acc, Acc).
build_replay_boards([Col|Rest], Board, Turn, Acc, Final) :-
    ( valid_move(Board, Col) -> drop(Board, Col, Turn, NB) ; NB = Board ),
    other(Turn, Next),
    build_replay_boards(Rest, NB, Next, [NB|Acc], Final).

replay_interactive(File) :-
    ( load_log(Moves, File) ->
        setup_replay(Moves),
        write('  Perintah: next. / prev. / jump(N). / export(ascii,\'f.txt\'). / export(json,\'f.json\'). / quit.'), nl,
        replay_show(0),
        replay_loop
    ; write('  >> Gagal memuat move-log.'), nl
    ).

replay_show(Idx) :-
    replay_state(Boards, Moves, _),
    length(Boards, Total), Max is Total - 1,
    nth1_index(Idx, Boards, B),
    format("~n  Posisi ~w / ~w~n", [Idx, Max]),
    print_board(B),
    ( Idx > 0 -> nth1(Idx, Moves, LastCol), format("  (langkah ke-~w: kolom ~w)~n", [Idx, LastCol]) ; true ),
    ( won(B, x) -> write('  >> Posisi ini: X MENANG.'), nl
    ; won(B, o) -> write('  >> Posisi ini: O MENANG.'), nl
    ; board_full(B) -> write('  >> Posisi ini: SERI (papan penuh).'), nl
    ; true
    ).

nth1_index(0, [H|_], H) :- !.
nth1_index(N, [_|T], X) :- N > 0, N1 is N - 1, nth1_index(N1, T, X).

replay_next :-
    replay_state(Boards, Moves, Idx),
    length(Boards, Total), Max is Total - 1,
    ( Idx < Max ->
        Idx1 is Idx + 1,
        retractall(replay_state(_,_,_)), assertz(replay_state(Boards, Moves, Idx1)),
        replay_show(Idx1)
    ; write('  >> Sudah di posisi terakhir.'), nl
    ).

replay_prev :-
    replay_state(Boards, Moves, Idx),
    ( Idx > 0 ->
        Idx1 is Idx - 1,
        retractall(replay_state(_,_,_)), assertz(replay_state(Boards, Moves, Idx1)),
        replay_show(Idx1)
    ; write('  >> Sudah di posisi awal.'), nl
    ).

replay_jump(N) :-
    replay_state(Boards, Moves, _),
    length(Boards, Total), Max is Total - 1,
    ( integer(N), N >= 0, N =< Max ->
        retractall(replay_state(_,_,_)), assertz(replay_state(Boards, Moves, N)),
        replay_show(N)
    ; format("  >> Posisi harus antara 0 dan ~w.~n", [Max])
    ).

replay_loop :-
    write('  > '), read(Input),
    replay_dispatch(Input).

replay_dispatch(next) :- !, replay_next, replay_loop.
replay_dispatch(prev) :- !, replay_prev, replay_loop.
replay_dispatch(jump(N)) :- !, replay_jump(N), replay_loop.
replay_dispatch(export(ascii,F)) :- !, export_replay_ascii(F), replay_loop.
replay_dispatch(export(json,F)) :- !, export_replay_json(F), replay_loop.
replay_dispatch(quit) :- !.
replay_dispatch(end_of_file) :- !.
replay_dispatch(_) :- write('  >> Perintah tak dikenal.'), nl, replay_loop.

export_replay_ascii(File) :-
    replay_state(Boards, Moves, _),
    open(File, write, S),
    export_ascii_frames(Boards, Moves, 0, S),
    close(S),
    format("  >> Diekspor (ASCII animation) ke ~w~n", [File]).

export_ascii_frames([], _, _, _).
export_ascii_frames([B|Bs], Moves, Idx, S) :-
    format(S, "~n=== Posisi ~w ===~n", [Idx]),
    export_board_to_stream(B, S),
    ( Moves = [Col|MRest] -> format(S, "langkah berikut: kolom ~w~n", [Col]), M2 = MRest ; M2 = [] ),
    Idx1 is Idx + 1,
    export_ascii_frames(Bs, M2, Idx1, S).

export_board_to_stream(Board, S) :-
    ( between(1, 6, FromTop), Row is 7 - FromTop, export_row(Board, Row, S), fail ; true ),
    format(S, "  ---------------~n", []),
    format(S, "   1 2 3 4 5 6 7~n", []).

export_row(Board, Row, S) :-
    format(S, "  | ", []),
    ( between(1, 7, Col), cell(Board, Col, Row, V), symbol(V, Sym), format(S, "~w ", [Sym]), fail ; true ),
    format(S, "|~n", []).

export_replay_json(File) :-
    replay_state(_, Moves, _),
    open(File, write, S),
    write(S, '{"moves":['),
    export_json_moves(Moves, S),
    write(S, ']}'), nl(S),
    close(S),
    format("  >> Diekspor (JSON) ke ~w~n", [File]).

export_json_moves([], _).
export_json_moves([M], S) :- !, write(S, M).
export_json_moves([M|Rest], S) :- write(S, M), write(S, ','), export_json_moves(Rest, S).

% ============================================================
%  Puzzle Mode (loop ringan, papan puzzle kecil & tetap -- aman
%  tanpa pola failure-driven karena tak ada pencarian minimax
%  dalam1 di dalamnya)
% ============================================================
puzzle_menu :-
    nl, write('  === Puzzle Mode ==='), nl,
    findall(Id, puzzle_fact(Id,_,_,_), Ids),
    print_puzzle_ids(Ids),
    write('  Pilih nomor puzzle (akhiri titik, 0 utk kembali) : '),
    read(PID),
    handle_puzzle_choice(PID).

print_puzzle_ids([]).
print_puzzle_ids([I|Rest]) :- format("    Puzzle ~w~n", [I]), print_puzzle_ids(Rest).

handle_puzzle_choice(0) :- !.
handle_puzzle_choice(end_of_file) :- !.
handle_puzzle_choice(PID) :-
    integer(PID), puzzle_fact(PID, Board, Turn, Desc), !,
    nl, format("  Puzzle ~w~n~n  ~w~n", [PID, Desc]),
    print_board(Board),
    piece_name(Turn, Nm),
    format("  Kolom pilihan (~w, akhiri titik) : ", [Nm]),
    read(AnsCol),
    judge_puzzle(Board, Turn, AnsCol),
    puzzle_menu.
handle_puzzle_choice(_) :-
    write('  >> Puzzle tidak ditemukan.'), nl,
    puzzle_menu.

judge_puzzle(Board, Turn, AnsCol) :-
    integer(AnsCol), check_puzzle_answer(Board, Turn, AnsCol, correct), !,
    nl, write('  Correct!'), nl, write('  Winning Move Found.'), nl, nl.
judge_puzzle(Board, Turn, _) :-
    nl, write('  Incorrect.'), nl,
    ( puzzle_solution_hint(Board, Turn, SolCol) ->
        format("  AI memiliki langkah kemenangan/blokir di kolom ~w.~n~n", [SolCol])
    ; nl
    ).

% ============================================================
%  Menu utama
% ============================================================
banner :-
    nl,
    write('==========================================='), nl,
    write('     CONNECT FOUR  -  GNU Prolog + AI       '), nl,
    write('     minimax + alpha-beta + fitur lanjutan   '), nl,
    write('==========================================='), nl, nl.

play :-
    load_stats,
    banner,
    menu_loop.

menu_loop :-
    repeat,
        show_menu,
        read(Choice),
        do_menu(Choice),
    !.

show_menu :-
    nl, write('Menu Utama:'), nl,
    write('   1. Kamu (X) vs AI (O)'), nl,
    write('   2. AI (X) vs Kamu (O)   [AI jalan duluan]'), nl,
    write('   3. Dua Pemain (X vs O)'), nl,
    write('   4. Demo AI vs AI'), nl,
    write('   5. Muat permainan tersimpan'), nl,
    write('   6. Replay interaktif riwayat'), nl,
    write('   7. Lihat statistik'), nl,
    write('   8. Benchmark AI'), nl,
    write('   9. AI vs AI Tournament'), nl,
    write('  10. Puzzle Mode'), nl,
    write('  11. Keluar'), nl,
    write('Pilih (akhiri titik) : ').

do_menu(1) :- !, adaptive_suggestion, ask_difficulty(D), ask_style(_), start_game(human, ai, D), fail.
do_menu(2) :- !, adaptive_suggestion, ask_difficulty(D), ask_style(_), start_game(ai, human, D), fail.
do_menu(3) :- !, start_game(human, human, 4), fail.
do_menu(4) :- !,
    ask_difficulty(D), ask_style(_),
    retractall(player_type(_,_)),
    assertz(player_type(x, ai)), assertz(player_type(o, ai)),
    retractall(undo_stack(_)), assertz(undo_stack([])),
    retractall(redo_stack(_)), assertz(redo_stack([])),
    retractall(move_log(_)), assertz(move_log([])),
    clear_last,
    initial_board(B), set_state(B, x, D),
    ( catch(game_loop, quit_game, true) -> true ; true ),
    fail.
do_menu(5) :- !,
    write("Nama file (mis. 'game.txt'.) : "), read(File),
    ( load_game(B, Turn, D, File)
    -> retractall(player_type(_,_)),
       assertz(player_type(x, human)), assertz(player_type(o, ai)),
       set_level(custom),
       retractall(undo_stack(_)), assertz(undo_stack([])),
       retractall(redo_stack(_)), assertz(redo_stack([])),
       retractall(move_log(_)), assertz(move_log([])),
       clear_last,
       set_state(B, Turn, D),
       format("  Dimuat. Giliran: ~w~n", [Turn]),
       ( catch(game_loop, quit_game, true) -> true ; true )
    ;  write('  >> Gagal memuat.'), nl ),
    fail.
do_menu(6) :- !,
    write("Nama file move-log (mis. 'log.txt'.) : "), read(File),
    replay_interactive(File), fail.
do_menu(7) :- !, show_stats, fail.
do_menu(8) :- !,
    write('Kedalaman maksimum (1-5, akhiri titik) : '), read(MaxD),
    ( integer(MaxD), MaxD >= 1, MaxD =< 5 -> run_benchmark(MaxD) ; write('  >> Harus antara 1-5.'), nl ),
    fail.
do_menu(9) :- !,
    write('Kedalaman AI A (akhiri titik) : '), read(DA),
    write('Kedalaman AI B (akhiri titik) : '), read(DB),
    write('Jumlah match (akhiri titik) : '), read(N),
    ( integer(DA), integer(DB), integer(N), N > 0 ->
        ( ( DA > 3 ; DB > 3 ), N > 10 ->
            write('  >> Peringatan: kedalaman tinggi + banyak match bisa makan waktu lama.'), nl
        ; true ),
        run_tournament(DA, DB, N)
    ; write('  >> Input tidak valid.'), nl
    ),
    fail.
do_menu(10) :- !, puzzle_menu, fail.
do_menu(11) :- !, write('Sampai jumpa!'), nl.
do_menu(end_of_file) :- !.
do_menu(_) :- write('  >> Pilihan tidak valid.'), nl, fail.

ask_difficulty(Depth) :-
    repeat,
        nl, write('Tingkat kesulitan:'), nl,
        write('  1. Mudah   (dangkal + variasi acak)'), nl,
        write('  2. Sedang  (kedalaman 4)'), nl,
        write('  3. Sulit   (kedalaman 5)'), nl,
        write('  4. Expert  (kedalaman 5 + opening book + heuristik lebih baik)'), nl,
        write('  5. Custom  (pilih 1-5)'), nl,
        write('Pilih (akhiri titik) : '),
        read(C),
        set_difficulty(C, Depth),
    !.

set_difficulty(1, 2) :- !, set_level(mudah).
set_difficulty(2, 4) :- !, set_level(sedang).
set_difficulty(3, 5) :- !, set_level(sulit).
set_difficulty(4, 5) :- !, set_level(expert).
set_difficulty(5, D) :- !,
    repeat, write('Kedalaman 1-5 (akhiri titik) : '), read(D0),
    ( integer(D0), D0 >= 1, D0 =< 5 -> D = D0, set_level(custom) ; write('  >> 1-5 saja.'), nl, fail ), !.
set_difficulty(end_of_file, 4) :- !, set_level(sedang).
set_difficulty(_, _) :- write('  >> Pilihan tidak valid.'), nl, fail.

set_level(L) :- retractall(diff_level(_)), assertz(diff_level(L)).

ask_style(Style) :-
    repeat,
        nl, write('Gaya bermain AI (Personality):'), nl,
        write('  1. Balanced   (seimbang)'), nl,
        write('  2. Aggressive (menyerang)'), nl,
        write('  3. Defensive  (bertahan)'), nl,
        write('  4. Random     (acak, tetap ambil menang/blokir)'), nl,
        write('Pilih (akhiri titik) : '),
        read(C),
        set_style_choice(C, Style),
    !.

set_style_choice(1, balanced) :- !, set_style(balanced).
set_style_choice(2, aggressive) :- !, set_style(aggressive).
set_style_choice(3, defensive) :- !, set_style(defensive).
set_style_choice(4, random) :- !, set_style(random).
set_style_choice(end_of_file, balanced) :- !, set_style(balanced).
set_style_choice(_, _) :- write('  >> Pilihan tidak valid.'), nl, fail.

set_style(S) :- retractall(ai_style(_)), assertz(ai_style(S)).

:- initialization(play).