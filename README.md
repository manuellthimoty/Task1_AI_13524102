# Connect Four — GNU Prolog + AI (Minimax + Alpha-Beta + Fitur Lanjutan)

Proof of Concept untuk **Task #1 Seleksi Laboratorium Intelegensi Buatan** —
permainan papan **Connect Four (7×6)** dengan AI **minimax + alpha-beta
pruning**, dilengkapi 10 fitur wajib dan sejumlah fitur bonus (Transposition
Table, Explainable AI, Opening Book, AI Personality, Search Tree
Visualization, Tournament, Benchmark, Puzzle Mode, Zobrist Hash, Principal
Variation, Undo/Redo tak terbatas, Replay interaktif + export, dan lainnya),
ditulis sepenuhnya di **GNU Prolog**.

> Repo: `Task1_AI_(NIM)` — ganti `(NIM)` dengan NIM kamu sebelum submit.

---

## 1. Cara Menjalankan

Butuh **GNU Prolog** (`gprolog`):

```bash
gprolog --consult-file connect4.pl
```

Program otomatis menampilkan menu (`:- initialization(play).`). Semua input
memakai `read/1`, jadi **setiap input diakhiri titik `.`** seperti query
Prolog biasa: `1.`, `hint.`, `save('game.txt').`, `jump(5).`, dsb.

## 2. Menu Utama

```
 1. Kamu (X) vs AI (O)
 2. AI (X) vs Kamu (O)   [AI jalan duluan]
 3. Dua Pemain (X vs O)
 4. Demo AI vs AI
 5. Muat permainan tersimpan
 6. Replay interaktif riwayat
 7. Lihat statistik
 8. Benchmark AI
 9. AI vs AI Tournament
10. Puzzle Mode
11. Keluar
```

Mode 1/2/4 akan menanyakan **tingkat kesulitan** dan **gaya bermain AI**
sebelum memulai.

## 3. Perintah Dalam Permainan

| Perintah | Fungsi |
|---|---|
| `1.` … `7.` | jatuhkan bidak ke kolom |
| `hint.` | 3 kolom terbaik menurut AI + rekomendasi |
| `analysis.` | Position Analysis (center/threat/connect-2/3/total) |
| `heatmap.` | evaluasi seluruh kolom, kolom terbaik ditandai `*` |
| `tree.` | visualisasi search tree 2-ply dengan alpha-beta nyata |
| `complexity.` | branching factor, estimasi node, node terkunjungi, efisiensi pruning |
| `pv.` | Principal Variation (garis terbaik hasil pencarian) |
| `zobrist.` | Zobrist hash posisi saat ini |
| `explain.` | alasan di balik langkah terakhir AI |
| `undo.` / `redo.` | batalkan / ulangi langkah — **tak terbatas** |
| `board.` | tampilkan papan lagi |
| `save('f.txt').` | simpan permainan |
| `savelog('f.txt').` | simpan riwayat langkah (untuk menu Replay) |
| `help.` | daftar perintah |
| `quit.` | kembali ke menu |

Jika sebuah langkah membuat lawan bisa menang giliran berikutnya, program
menampilkan **peringatan Smart Hint** dan meminta konfirmasi `(y/n)` sebelum
melanjutkan.

### Perintah dalam Replay Interaktif (menu 6)

| Perintah | Fungsi |
|---|---|
| `next.` / `prev.` | maju / mundur satu posisi |
| `jump(N).` | lompat langsung ke posisi ke-N |
| `export(ascii,'f.txt').` | ekspor seluruh replay sebagai ASCII animation |
| `export(json,'f.json').` | ekspor riwayat langkah sebagai JSON |
| `quit.` | kembali ke menu |

## 4. Daftar Fitur

### Wajib

1. **Transposition Table** — cache nilai evaluasi *exact* (hasil pencarian
   penuh tanpa cutoff), dikosongkan tiap awal langkah AI.
2. **Statistik AI** — Depth, Nodes, Alpha Cutoff, Beta Cutoff, Time, tampil
   otomatis tiap AI berpikir (kecuali gaya Random, yang tak melakukan
   pencarian sama sekali).
3. **Visualisasi Search Tree** (`tree.`) — pohon 2-ply dengan alpha-beta
   **sungguhan**, sehingga label "Beta Cutoff" yang tampil adalah cutoff
   nyata, bukan simulasi.
4. **Explainable AI** (`explain.`) — alasan: kontrol center, blokir ancaman,
   membentuk Connect-3, membuka fork — plus Evaluation Score.
5. **Opening Book** — beberapa entri pembuka ilustratif (lihat Catatan
   Implementasi).
6. **4 Tingkat Kesulitan** — Mudah (dangkal+acak), Sedang, Sulit, dan
   **Expert** (kedalaman 5 + opening book + heuristik gaya-sadar), plus
   Custom.
7. **AI vs AI Tournament** (menu 9) — N pertandingan otomatis, sisi
   ditukar tiap match genap untuk keadilan.
8. **Benchmark AI** (menu 8) — tabel Depth/Nodes/Time untuk kedalaman 1–5.
9. **Heat Map** (`heatmap.`) — evaluasi seluruh 7 kolom sekaligus.
10. **Undo & Redo tak terbatas** — riwayat penuh, bukan cuma satu langkah.

### Bonus

1. **Replay Interaktif** (`next.`/`prev.`/`jump(N).`) — menu 6.
2. **Export Replay** — ASCII animation & JSON.
3. **Position Analysis** (`analysis.`) — Center Control, Threat, Connect-2,
   Connect-3, Opponent Threat, Total.
4. **AI Personality** — Balanced / Aggressive / Defensive / Random, via
   bobot heuristik berbeda (Random tetap kompeten taktis: selalu ambil
   kemenangan instan / blokir ancaman tunggal).
5. **Smart Hint** — peringatan `(y/n)` sebelum langkah yang membuka
   kemenangan lawan.
6. **Zobrist Hash** (`zobrist.`) — hash posisi papan, didemonstrasikan
   terpisah dari Transposition Table (lihat Catatan Implementasi).
7. **Principal Variation** (`pv.`) — garis terbaik + skor evaluasi.
8. **Adaptive AI** — saran (bukan paksaan) penyesuaian kesulitan berdasarkan
   rasio menang/kalah tersimpan.
9. **Analisis Kompleksitas** (`complexity.`) — branching factor, estimasi
   node, node sungguhan, efisiensi pruning.
10. **Puzzle Mode** (menu 10) — 5 puzzle, jawaban diverifikasi programatik
    (bukan hardcode).

## 5. Aturan Main

1. Papan 7 kolom (1–7) × 6 baris. X selalu jalan pertama (kecuali mode
   "AI (X) vs Kamu").
2. Bidak mengisi sel kosong **terbawah** pada kolom yang dipilih.
3. Kolom penuh tidak bisa dipilih (ditolak, diminta ulang).
4. Menang bila 4 bidak sejajar: horizontal, vertikal, atau diagonal.
5. Papan penuh tanpa 4 sejajar = seri.

## 6. Berkas dalam Repo

| Berkas | Keterangan |
|---|---|
| `connect4.pl` | Seluruh program |
| `README.md` | Dokumen ini |
| `contoh_game.txt` | Contoh permainan tersimpan (menu **5**) |
| `contoh_log.txt` | Contoh move-log (menu **6**, juga bisa untuk `savelog`) |

`stats.txt` dibuat otomatis saat permainan pertama selesai.

## 7. Pemetaan Enam Konsep Wajib

| Konsep | Di mana |
|---|---|
| **Rekurens** | `negamax/7`, `nm_loop/10`, `drop_in_col/3`, `four/6`, `principal_variation`, `build_replay_boards`, pencetakan papan/pohon |
| **List** | Papan (7×6), jendela 4-sel, `move_log`, `undo_stack`/`redo_stack` (snapshot 4-tuple), `Boards` list replay |
| **Cut** | Commit `best_move_styled/5`; beta cutoff `nm_loop`; klausa `dispatch/6`, `set_difficulty`, `set_style_choice` |
| **Fail** | Tolak langkah ilegal; `undo`/`redo` mem-`fail`-kan giliran utk reclaim stack; `play_one_match` failure-driven |
| **Loop** | `repeat…fail` (game loop, tournament, menu); `between…fail` (papan, tree, ekspor ASCII) |
| **File Processing** | `save_game`/`load_game`, `save_log`/`load_log`, `load_stats`/`save_stats`, `export_replay_ascii`/`export_replay_json` |

## 8. Catatan Implementasi (Trade-off yang Disengaja)

- **GNU Prolog tanpa GC otomatis di global stack.** Solusi: game loop
  *failure-driven* — tiap langkah diproses lalu di-`fail`-kan agar Prolog
  backtrack & mereklaim stack. Berlaku juga untuk Tournament
  (`play_one_match`) dan mode Demo.
- **GNU Prolog di lingkungan ini TIDAK mendukung bignum** — integer asli
  overflow diam-diam sekitar 2^60 (representasi ~61-bit bertanda). Tabel
  Zobrist awalnya memakai kombinasi shift 40-bit+20-bit dan overflow
  (ditemukan saat testing, nilai hash jadi tak terduga); diperbaiki dengan
  kombinasi shift yang lebih kecil (~58-bit efektif, aman).
- **Transposition Table hanya menyimpan nilai EXACT** (hasil `nm_loop` yang
  selesai penuh tanpa cutoff), bukan bound dari cutoff — supaya selalu aman
  dipakai ulang tanpa perlu flag EXACT/LOWERBOUND/UPPERBOUND yang lebih
  rumit. Tabel dikosongkan di **awal setiap langkah AI** (bukan sepanjang
  game) untuk mencegah database membengkak tanpa batas.
- **Klasifikasi Alpha vs Beta Cutoff** memakai kesetaraan negamax↔minimax
  standar: cutoff pada node dengan `Player == RootPlayer` setara node MAX
  klasik (**Beta Cutoff**); pada node lawan setara node MIN (**Alpha
  Cutoff**).
- **Instrumentasi (statistik+TT) menambah overhead nyata**: pada papan awal
  kedalaman 5, pencarian tanpa instrumentasi ≈ 537 ms, dengan instrumentasi
  ≈ 887 ms — karena `assert`/`retract` per node relatif mahal di GNU
  Prolog dibanding penghematan yang didapat TT pada skala pohon ini. Tetap
  sepenuhnya playable; didokumentasikan apa adanya sebagai temuan jujur,
  bukan disembunyikan.
- **Opening Book bersifat ilustratif** (~8 entri untuk 1–2 langkah
  pembuka), **bukan** basis data solved-game Connect Four yang lengkap
  (itu perlu jutaan posisi hasil perfect-play search). Tujuannya
  mendemonstrasikan mekanisme "cek buku dulu sebelum minimax", bukan
  mengklaim permainan sempurna.
- **Zobrist Hash didemonstrasikan terpisah dari Transposition Table.** TT
  proyek ini tetap memakai representasi papan (list) sebagai kunci — bebas
  collision sepenuhnya karena unifikasi struktural. Zobrist hash dihitung
  dan ditampilkan sebagai identitas posisi; pada engine performa-tinggi
  dengan representasi bitboard, hash inilah yang lazim dipakai sebagai
  kunci TT.
- **Principal Variation adalah aproksimasi** — dibangun lewat pemanggilan
  `best_move` berulang pada kedalaman menurun, bukan diekstraksi langsung
  dari satu pencarian negamax (yang perlu menyimpan rantai langkah terbaik
  di tiap node — perubahan lebih invasif ke inti pencarian yang sudah
  teruji).
- **Expert tetap kedalaman 5, bukan 6.** Kedalaman 6 dari papan awal
  overflow global stack default (diuji ulang setelah penambahan TT —
  hasilnya tetap overflow, TT tidak cukup menolong pada kasus ini).
- **AI vs AI Tournament awalnya deterministik → semua match identik
  (draw terus).** Diperbaiki dengan dua langkah: (a) pemilihan langkah
  "mendekati-terbaik" (`best_move_easy`, bukan `best_move` murni) supaya
  tiap game bisa berbeda, (b) sisi X/O ditukar pada match bernomor genap
  agar tak ada bias keuntungan-jalan-duluan.
- **Puzzle Mode diverifikasi programatik**: jawaban benar = kolom tersebut
  memberi kemenangan instan ATAU memblokir ancaman instan lawan — dicek
  lewat `immediate_win`/`opponent_threats`, bukan jawaban hardcode. Dua
  dari lima puzzle awal ternyata salah konstruksi saat pertama dites
  (satu tidak benar-benar membentuk ancaman, satu lagi membentuk ancaman
  ganda yang tak bisa diblokir satu langkah) — keduanya diperbaiki dan
  diverifikasi ulang.
- **Kuirk `format/2` GNU Prolog**: literal karakter `%` di dalam control
  string `format` menyebabkan `domain_error` — semua tempat yang perlu
  mencetak tanda persen memakai `write('%')` terpisah. `format(atom(A),
  ...)` (mencetak ke atom) juga tidak didukung; solusinya mencetak
  langsung ke stream.
- **`xor` bukan infix operator** di GNU Prolog — harus dipanggil sebagai
  fungsi `xor(A,B)`. `**` selalu mengembalikan float meski kedua operand
  integer; `^` dipakai untuk pemangkatan integer (estimasi node pada
  Analisis Kompleksitas).

## 9. Contoh Sesi

```
1.                      % Kamu vs AI
4.                      % kesulitan Expert
2.                      % gaya Aggressive
4.                      % X jatuh di kolom 4 (AI otomatis membalas + statistik tampil)
analysis.               % lihat Position Analysis
tree.                   % lihat visualisasi search tree
undo.                   % batalkan langkah terakhir
redo.                   % ulangi lagi
save('game.txt').       % simpan
quit.                   % kembali ke menu
9.                      % AI vs AI Tournament
2.
4.
6.                      % 6 pertandingan
11.                     % keluar
```