# PRD — Yoman Companion (v0.4)

> Status: **keputusan utama sudah dikunci**; siap masuk MVP. Sisa ❓ di §13.
> Riwayat:
> - v0.1 (19 Nov 2026): companion hanya muncul saat Claude Code aktif.
> - v0.2 (19 Nov 2026): selalu menyala sejak login, bisa di-toggle, bereaksi ke cursor, ketikan, dan musik, serta bisa ngobrol. Referensi Comnyang ditambahkan.
> - v0.3 (19 Nov 2026): diputuskan Apple on-device LLM, bahasa Inggris, pixel art hasil generate, peek dari pinggir layar, Apple Music + Spotify, toggle ⌥⌘F.

> - v0.4 (19 Nov 2026): **karakter diganti menjadi kucing hitam pixel art orisinal** (bukan Frieren); fitur desktop pet ala Comnyang ditambahkan. Bagian v0.4 di bawah ini menggantikan keputusan D5–D7 dan §8–§9 yang bertentangan.

---

## v0.4: Pivot ke kucing hitam

**Karakter:** "Yoman", kucing hitam pixel art orisinal (sel 64×64, kalung merah dengan lonceng, mata kuning-hijau). Dibuat sepenuhnya dari kode di `tools/make_cat.swift`, jadi aman di-commit. Suara meong/mrrp disintesis (`tools/make_sounds.swift`); dengkuran memakai suara sistem macOS "Purr".

**Fitur (status MVP v0.2):**

| Fitur | Pemicu | Status |
|---|---|---|
| Mata mengikuti cursor | gerak mouse | ✅ |
| Diseret melar seperti mochi, dilempar, memantul | drag | ✅ |
| Berburu cursor: jongkok, goyang, menerkam ke arah cursor | cursor cepat di dekatnya | ✅ |
| Dielus → mendengkur + hati | cursor digoyang di atas kepala | ✅ |
| Menguleni (kneading) saat mengetik | ritme ketik global (izin Accessibility; isi tombol tidak dibaca) | ✅ |
| Overheat: merah + uap | mengetik ≥ 7 tombol/detik | ✅ |
| Gulungan kertas terurai | scroll | ✅ |
| Berpikir saat Claude bekerja; lompat + meong saat selesai; angkat paw saat butuh kamu | hook Claude Code | ✅ |
| Pengingat peregangan: kucing membesar dan meregang | tiap 50 menit (bisa diatur) | ✅ |
| Pengingat minum: kucing minum dari mangkuk | tiap 60 menit (bisa diatur) | ✅ |
| Pomodoro (fokus/istirahat, istirahat panjang tiap ke-4) | menu bar | ✅ |
| Pengingat pesan pada jam tertentu | menu → Remind Me At… | ✅ |
| Pesan tersemat di atas kepala | menu → Pin a Message… | ✅ |
| Nama panggilan ("Jagoan") | Settings | ✅ |
| Mode intip dari pinggir layar | app fullscreen (video) | ✅ |
| Tidur setelah 10 menit tanpa input | idle sistem | ✅ |
| Settings (nama, ukuran, suara, toggle tiap reaksi, interval) | menu → Settings… | ✅ |

**Revisi visual & gerak (19 Nov 2026):** siluet hitam dengan outline putih (terbaca di wallpaper gelap/terang), mata putih dengan pupil vertikal, tuts keyboard di bawah paw saat mengetik, 2–8 frame per animasi. Gerakan: hop halus via Core Animation (berjalan di render server), "pop" pegas saat berganti state, drag mochi yang melar dan berayun dari titik pegangan. App di-sign dengan designated requirement tetap (bundle id) agar izin Accessibility tidak hilang setiap kali di-build ulang.

**Performa terukur (M2 Air):** ~0–1% CPU tanpa input; ~5% saat mouse terus bergerak (sebagian besar overhead event mouse global); ~3% sesaat saat hop; memori ~20 MB.

**Ditunda:** obrolan Apple Foundation Models, reaksi musik Apple Music/Spotify, warna/pola bulu custom.

---

## 1. Ringkasan

Yoman Companion adalah **karakter pixel art Frieren di desktop macOS** yang **ikut menyala saat login** dan bisa **di-on/off dengan ⌥⌘F**. Dia hidup di layar: matanya mengikuti cursor, bereaksi saat kamu mengetik, ikut bergoyang saat Apple Music/Spotify memutar lagu, bisa diseret ke mana saja dengan gerakan kenyal, mengintip dari pinggir layar saat ada aplikasi fullscreen, dan bisa diajak ngobrol dalam **bahasa Inggris** memakai **model AI on-device Apple**. Status kerja **Claude Code** (aplikasi Claude desktop maupun CLI) menjadi sumber reaksi utamanya.

## 2. Keputusan yang sudah dikunci

| # | Topik | Keputusan |
|---|---|---|
| D1 | Platform & stack | macOS, Swift 6 native (AppKit + SwiftUI), Swift Package Manager |
| D2 | Siklus hidup | Menyala otomatis saat login; toggle on/off lewat menu bar dan **⌥⌘F** |
| D3 | Integrasi Claude | Hook Claude Code untuk aplikasi Claude desktop + CLI |
| D4 | Approval | v1: hanya pemberitahuan + klik untuk membuka Claude. Tombol Izinkan/Tolak masuk backlog |
| D5 | Mesin obrolan | **Apple Foundation Models** (on-device, gratis, offline, privat) |
| D6 | Bahasa | **Inggris** untuk semua dialog, obrolan, dan UI |
| D7 | Gaya visual | **Pixel art**, gaya sprite sheet seperti waifu-assistance; aset **di-generate** lalu dirapikan |
| D8 | Fullscreen / video | **Mengintip dari pinggir layar** (peek mode) |
| D9 | Musik | **Apple Music + Spotify** saja |

## 3. Referensi

- **waifu-assistance** (github.com/reubinars/waifu-assistance): pola *hook → bridge → socket → app*, format sprite sheet + JSON (`pet.json`: sel 64×64, 5 state, maksimal 20 warna, alpha biner, sampling *nearest*), installer hook yang aman, pemberitahuan yang tidak mencuri fokus.
- **Comnyang** (comnyang.com): perilaku desktop pet: mata mengikuti mouse, *mochi drag*, dielus, reaksi mengetik + *overheat*, reaksi scroll, berpikir/lompat mengikuti agent AI, peek mode, Pomodoro & pengingat, tanpa telemetri.

## 4. Tujuan & non-tujuan

**Tujuan**
- G1. Menyala saat login, toggle ⌥⌘F, posisi terakhir diingat.
- G2. Reaksi < 100 ms ke cursor/keyboard dan < 300 ms ke event Claude Code.
- G3. Terasa fluid **walaupun pixel art** (lihat §8).
- G4. Ringan untuk MacBook Air M2: < 1% CPU saat diam, ≈ 0% saat OFF.
- G5. Tidak mengganggu: tidak mencuri fokus, klik tembus di luar karakter, peek saat fullscreen.
- G6. Privasi: isi ketikan tidak dibaca; obrolan tidak keluar dari Mac; tanpa telemetri.

**Non-tujuan (v1):** pengganti Claude Code; distribusi publik (aset Frieren berhak cipta); platform selain macOS Apple Silicon; bahasa selain Inggris.

## 5. Siklus hidup app

| Kondisi | Perilaku |
|---|---|
| Login | App jalan otomatis (`SMAppService` Login Item), karakter muncul |
| ⌥⌘F / menu → OFF | Karakter hilang, semua monitor dilepas, CPU ≈ 0; ikon menu bar tetap ada |
| ⌥⌘F / menu → ON | Muncul lagi di posisi terakhir |
| Ada app fullscreen | Pindah ke pinggir layar terdekat dan hanya kepalanya yang mengintip; kembali saat fullscreen selesai. Hover → keluar sedikit |
| Quit | Keluar total; hook tetap aman (bridge exit 0 jika app mati) |

## 6. Sumber input

| Input | Cara teknis | Izin macOS |
|---|---|---|
| Claude Code | Hook `~/.claude/settings.json` → `yoman-bridge` → Unix socket | – |
| Cursor | `NSEvent.mouseLocation` per frame saat terlihat; global monitor untuk klik | – |
| Ketikan | Global monitor `.keyDown`; **hanya timestamp**, isi dibuang | Accessibility |
| Scroll | Global monitor `.scrollWheel` | – |
| Musik | ScriptingBridge/AppleScript ke **Music.app** & **Spotify**: state play/pause, judul, artis. Hanya menanyai app yang sedang berjalan; polling ringan (≈ 2 dtk) hanya saat salah satunya terbuka; plus notifikasi `com.apple.Music.playerInfo` / `com.spotify.client.PlaybackStateChanged` agar event-driven | Automation (per app) |
| Fullscreen | `NSWorkspace` + `CGWindowListCopyWindowInfo` untuk mendeteksi jendela fullscreen | – |

## 7. Integrasi Claude Code

**Dukungan aplikasi Claude desktop:** tab Code di Claude desktop menjalankan binary Claude Code yang sama (`CLAUDE_CODE_ENTRYPOINT=claude-desktop`) dan sudah membaca `~/.claude/settings.json`. Jadi hook seharusnya ikut berjalan. **Langkah pertama MVP adalah spike untuk memastikannya.**

| Hook | State | Reaksi |
|---|---|---|
| `SessionStart` | `greet` | Menoleh, melambai |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `working` | Membaca grimoire, partikel sihir kecil |
| `PermissionRequest`, `Notification` | `needs_you` | Mengangkat tangan + bubble "Claude needs you" |
| `Stop`, `SubagentStop` | `done` | Lompat kecil / senyum tipis |
| `SessionEnd` | kembali ke perilaku desktop | – |
| Tanpa input > N menit | `sleep` | Tidur pulas |

- Multi-sesi dilacak lewat `session_id` + PID; watchdog PID tiap ~30 dtk membersihkan sesi yang mati.
- Klik karakter saat `needs_you` → aktifkan jendela Claude (`com.anthropic.claudefordesktop`) atau terminal asal sesi.
- Installer: `yoman-bridge hooks install|remove|status`, dengan backup `settings.json`, edit atomik, idempotent, dan hanya menyentuh entry Yoman.

## 8. Visual: pixel art yang terasa fluid

Pixel art frame-by-frame cenderung kaku. Strateginya: **pixel di dalam, gerakan halus di luar.**

1. **Sprite sheet bergaya waifu-assistance:** sel **64×64** (dirender dengan skala bilangan bulat, misal ×3 = 192 pt), maksimal ~20 warna, alpha biner, sampling *nearest neighbor* agar tetap tajam.
2. **Bagian terpisah untuk interaksi:** mata/pupil sebagai lapisan sendiri agar bisa mengikuti cursor per pixel tanpa menggambar ulang seluruh frame. Rambut/jubah opsional sebagai lapisan sendiri.
3. **Gerakan prosedural di atas sprite:** squash & stretch, pegas saat diseret/dilepas, bob napas, sedikit miring, lempar dengan inersia. Gerakan dihitung halus (sub-pixel) di 60 fps, sementara isi sprite tetap pixel-perfect.
4. **Lebih banyak frame per state** (6–8 frame idle, bukan 4) + transisi pendek antar-state (misal `working → done`).
5. **Render:** **Core Animation** (`CALayer` dengan `magnificationFilter = .nearest`) di `NSPanel` transparan. Dipilih menggantikan SpriteKit karena tidak memakai render loop terus-menerus: frame sprite hanya diganti sesuai durasinya (2–8×/detik), pupil hanya bergerak saat mouse bergerak, dan `CADisplayLink` 60 fps hanya aktif saat diseret atau memantul. Saat diam, CPU hampir nol.

### State animasi (sprite sheet)
`idle`, `blink`, `working`, `needs_you`, `done`, `sleep`, `dragged`, `typing`, `overheat`, `listening` (bergoyang mengikuti musik), `talking`, `peek`, `greet`, `petted`.

### Pipeline aset (generate)
1. Generate karakter dasar Frieren dalam gaya pixel 64×64 (pose depan, latar polos) untuk dijadikan **referensi identitas**.
2. Generate tiap state berdasarkan referensi itu, agar wajah, warna, dan pakaian konsisten.
3. **Script pembersih** (Python, lokal): hapus latar → alpha biner, kuantisasi ke palet ≤ 20 warna bersama, snap ke grid 64×64, rata-kan posisi anchor (kaki), lalu susun menjadi sprite sheet + `character.json`.
4. Rapikan manual di editor pixel (misal Aseprite/Pixelorama) bila ada frame yang melenceng.
5. **Placeholder dulu:** MVP memakai karakter sederhana agar kode tidak menunggu aset.

## 9. Obrolan (bahasa Inggris, on-device)

- **Mesin:** framework **FoundationModels** (model ~3B on-device Apple). Sudah tersedia di SDK macOS 27 pada Mac ini. Syarat: **Apple Intelligence aktif** di System Settings. App mengecek `SystemLanguageModel.default.availability`; jika tidak tersedia, obrolan dinonaktifkan dan celetukan scripted tetap jalan.
- **Persona:** instruksi sistem Frieren: tenang, datar, sedikit kering, menyukai sihir "tidak berguna", memandang waktu manusia sebagai sesuatu yang singkat, kadang menyebut perjalanannya. Jawaban pendek (1–3 kalimat) agar cocok di bubble.
- **Konteks yang disuntikkan:** jam/hari, lagu yang sedang diputar, nama project Claude aktif + statusnya, lama sesi kerja, nama kamu.
- **Celetukan otomatis:** kumpulan dialog scripted per event (sapaan, Claude selesai, lagu ganti, mengetik terlalu cepat, pengingat istirahat), dengan cooldown agar tidak cerewet. Opsional: model on-device memvariasikan kalimatnya.
- **Memori:** lokal (JSON): nama, preferensi, beberapa fakta yang kamu sebutkan.
- **UI:** klik dua kali karakter → bubble dengan kolom input; Esc untuk menutup. Bubble muncul tanpa mencuri fokus kecuali saat kamu membuka kolom input.
- **Tanpa TTS di v1.**

## 10. Daftar fitur & prioritas

### MVP (v0.1): "dia hidup di desktop"
- [x] **Spike:** pastikan hook Claude Code terkirim dari aplikasi Claude desktop
- [x] App menu bar + Login Item + toggle ⌥⌘F
- [x] Overlay transparan (`NSPanel` non-activating), drag ke mana saja, posisi diingat, klik tembus di luar karakter
- [x] Renderer Core Animation + loader `character.json` + karakter placeholder
- [x] State machine: idle, working, needs_you, done, sleep, dragged
- [x] Mata mengikuti cursor + drag kenyal (pegas, squash-stretch)
- [x] `yoman-bridge` + installer hook + reaksi ke Claude Code
- [x] Klik saat `needs_you` → buka Claude

### v0.2: "dia memperhatikan"
- [ ] Reaksi mengetik + overheat; reaksi scroll
- [ ] Reaksi musik Apple Music + Spotify (`listening` + bubble judul lagu)
- [ ] Peek mode saat fullscreen
- [ ] Celetukan scripted

### v0.3: "dia teman ngobrol"
- [ ] Obrolan Foundation Models + persona + konteks + memori
- [ ] Aset Frieren pixel art final (pipeline §8)
- [ ] Pomodoro, pengingat minum & peregangan

### Backlog
Tombol Izinkan/Tolak dari bubble; usage token Claude; berjalan di tepi jendela/Dock; mengejar cursor cepat; achievement "koleksi spell"; TTS suara sistem.

## 11. Kebutuhan non-fungsional

| Area | Target |
|---|---|
| CPU diam / OFF / animasi | < 1% / ≈ 0% / < 5% |
| RAM | < 80 MB (di luar memori model Apple yang dikelola sistem) |
| Latensi | input < 100 ms; hook < 300 ms; bridge selesai < 50 ms |
| Keandalan | app mati/crash tidak menghambat Claude Code |
| Privasi | isi ketikan tidak disimpan; obrolan on-device; tanpa telemetri |

## 12. Struktur project (rencana)

```
YomanCompanion/
├─ Package.swift
├─ Sources/
│  ├─ YomanApp/        # menu bar, overlay, Core Animation, state machine, input monitor, chat
│  ├─ YomanBridge/     # CLI yang dipanggil hook + installer
│  └─ YomanCore/       # model event, protokol socket, parser character.json (bisa dites)
├─ Tests/YomanCoreTests/
├─ Assets/placeholder/ # karakter placeholder (boleh di-commit)
├─ Assets/frieren/     # aset hasil generate (JANGAN di-commit ke repo publik)
├─ tools/sprite_clean.py
└─ docs/PRD.md
```

## 13. Risiko & pertanyaan terbuka

| Risiko | Mitigasi |
|---|---|
| Hak cipta Frieren | Pemakaian pribadi; `Assets/frieren/` masuk `.gitignore` |
| Hasil generate tidak konsisten antar-frame | Referensi identitas + script kuantisasi/snap + rapikan manual; mulai dari sedikit state |
| Apple Intelligence tidak aktif / tidak tersedia | Cek ketersediaan; fallback ke celetukan scripted |
| Hook tidak terkirim dari Claude desktop | Spike di awal; fallback: pantau file transcript `~/.claude/projects` |
| Izin Accessibility & Automation | Diminta bertahap saat fitur diaktifkan, dengan penjelasan |
| Gatekeeper | Build lokal + ad-hoc signing |

Keputusan tambahan (v0.3.1):
- Frieren memanggilmu **"Jagoan"**.
- `sleep` setelah **10 menit** tanpa input apa pun (diukur dari idle time sistem, tanpa izin tambahan).
- Skala tampilan bisa diatur nanti; default ×3.
- Repo akan di-push ke **GitHub privat**. Aset Frieren tetap di `.gitignore` sebagai pengaman.
