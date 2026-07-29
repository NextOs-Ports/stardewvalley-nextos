# Stardew Valley — native AArch64 port (Mono/.NET Android on plain Linux)

**Language / Idioma:** [English](#english) · [Português](#português)

A native Linux port of the **Android** release of Stardew Valley
(`com.chucklefish.stardewvalley` 1.6.15.3, arm64-v8a), running on low-power retro
handhelds — **no Android, no emulator, no container**. Our own ELF loader boots the
entire **Mono-Android / .NET 8 runtime** on glibc and drives the game from there.

It is a **BYO-data** project: not a single byte of game content — no APK, no assets,
no `libmonosgen`, no assembly store — is in this repository or in the released ZIP.
You supply your own legal copy.

## Download

Grab **`Stardew.Valley.NextOS.zip`** from the
[latest release](https://github.com/NextOs-Ports/stardewvalley-nextos/releases/latest)
and extract it into your device's ROM root (`/roms` on ArkOS/ROCKNIX/muOS/Knulli/batocera,
`/storage/roms` on EmuELEC/NextOS). Drop your own arm64-v8a APK inside
`ports/sdvnextos/` and launch it from the Ports menu — the first run extracts the data
by itself (~420 MB, a few minutes) and deletes the APK to free the card.

**Exit the game: SELECT + START.**

## Screenshots

Real framebuffer captures off real hardware — no upscaling, no mock-ups:

| | |
|---|---|
| ![Title screen at night, Mali-450](docs/screenshots/01-title-mali450-night.png) | ![Title screen by day, Mali-450](docs/screenshots/02-title-mali450-day.png) |
| ![Title screen on the R36S](docs/screenshots/03-title-r36s.png) | ![Farm gameplay on the R36S](docs/screenshots/04-gameplay-r36s.png) |

Top row: NextOS Elite handheld (Amlogic, **Mali-450**, GLES2 only, ~1 GB RAM) at
1280×720 — the animated day/night sky of the title screen, in the game's own
Portuguese localisation. Bottom row: **R36S / ArkOS** (RK3326, Mali-G31, KMSDRM) at
640×480, title and farm gameplay.

---

## English

### Status

**Playable end to end**, with real saves, on two very different devices:

| Device | Video | State |
|---|---|---|
| Mali-450 / Amlogic-old (EmuELEC, fbdev) | ES2 on fbdev, 1280×720 | playable, real save — the bench this port was born on |
| R36S / ArkOS (RK3326, Mali-G31) | ES2 over an ES3 context, KMSDRM, 640×480 | playable, real save, validated |
| Other AArch64 (Mesa/Panfrost, wayland, muOS…) | negotiated at runtime | should come up; no device here to confirm |

Character creation, the game's own in-game keyboard, first save written and validated
(a real 3 MB `SaveGameInfo` pair), gameplay, audio, VSync, and healthy memory
(~250–333 MB RSS, no relevant swap). The shipped `stardewvalley.multi` binary is built
in `debian:buster` (max GLIBC 2.17), so it runs on old and current CFW alike.

> The famous "fundamental allocator wall" (Mono asserting `lock-free-alloc.c:608`)
> turned out **not** to be a wall at all: Bionic and glibc number their `sysconf`
> constants differently (`_SC_PAGESIZE` = 39 on Bionic ≠ glibc), so Mono was told a
> garbage page size. Mapping the `_SC_*` constants fixed the "unfixable".

### How it works (architecture)

There is no Android, no Java and no Activity system — we fake all three:

1. Our ELF loader (`so_util`) loads the Bionic chain `libmonosgen-2.0.so` →
   `libxamarin-app.so` → `libmonodroid.so`, snapshotting exported symbols between
   stages.
2. A fake `JavaVM`/`JNIEnv` (flat vtable at the exact Bionic arm64 LP64 offsets) is
   handed to `JNI_OnLoad`, then `Java_mono_android_Runtime_init` runs the **complete**
   .NET-for-Android bootstrap (MonoVM 9.0.8.0) and returns cleanly.
3. Mono components and AOT images are loaded through the so-loader's own
   `dlopen`/`dlsym` (glibc `dlopen` dies on their lazy-PLT/IRELATIVE relocs);
   `libaot-*.dll.so` is deliberately refused so Mono falls back to JIT.
4. With the runtime up, we drive the `MainActivity` lifecycle by hand (`onCreate` →
   managed `OnCreate` → `Game.Run()`), and `MonoGameAndroidGameView` runs the managed
   game loop.
5. SDL2 owns the real ES2 context; the fake EGL10 surface just presents it to MonoGame.
   The backbuffer is forced opaque (alpha = 1) for the Amlogic fbdev compositor.
6. Audio: XACT/OpenAL — MonoGame's `libopenal32.so` is redirected to the system
   `libopenal.so.1`.

Nothing about the device is hardcoded: paths come from `/proc/self/exe`, and
resolution, GLES version, backbuffer format and audio backend are all negotiated at
runtime.

### Walls we broke

| Wall | Cause | Fix |
|---|---|---|
| Mono allocator assertion (`lock-free-alloc.c:608`, sgen pagesize) | `sysconf` `_SC_*` numbering differs Bionic ≠ glibc → `mono_pagesize` garbage | map Bionic `_SC_{39,40,96–99}` to real values |
| SIGBUS on Mono's global semaphore | `sem_t` is 16 B on Bionic vs 32 B on glibc | own `sem_*` implementation on futex |
| "No JavaVM registered with handle 0x0" (managed) | `GetJavaVM` missing from the fake vtable (slot 0x6D8) | implement it, return the fake VM |
| managed saw a pending exception after EVERY `FindClass` | `ExceptionOccurred`/`ExceptionCheck` sat at WRONG vtable offsets; the real slots hit the non-NULL default → the `Java.Lang.Throwable` typemap error was a **symptom** | move to the real offsets (idx 15 / idx 228) + `Push/PopLocalFrame` |
| SIGSEGV in `Memmove` reading any string | `Java.Interop` uses the UTF-16 path (`GetStringChars`), slots missing → default sentinel dereferenced | implement UTF-16 slots (`0x520/0x528/0x530`) |
| "JNIEnv::RegisterNatives() returned 2" | shim was `void` → managed read garbage from `x0` | return `int` 0 (JNI_OK) |
| ~520 MB RAM spike per music track | 258 MB `music.xwb` copied whole into a `MemoryStream` | fake asset stream exposes only the XACT metadata and turns the skip into a native `fseek` |
| `SetRenderTarget` silently ignored (no FBOs) | fake `Looper.myLooper()` made `SyncContext.Send` run on the background task | promote the worker to foreground in `myLooper` — UI-thread semantics restored |
| Mali corrupted after ~1500 frames | temporary GL trace wrappers | production dispatch returns the context entrypoints directly (14k+ frames stable) |
| no keyboard on `TextBox` fields | `ShowAndroidKeyboard` expects the Android IME | patched to open the game's own `TextEntryMenu` |
| save stuck / simulated "disk full" | offline network barrier + `Java.IO.File.get_UsableSpace` returning 0 | confirm the barrier, return the real `statvfs` |
| flicker/tearing | swap interval set before the context existed | `SDL_GL_SetSwapInterval(1)` once the context is current |
| game closed at "Saving…" on other devices | `getFilesDir` hardcoded to one device path | everything derives from `/proc/self/exe` (`$HOME` is no anchor — Mono rewrites it in `Runtime_init`) |
| phone-sized zoom (~13 tiles) | the fake `DisplayMetrics` reported a fixed 160 dpi | `MobileDisplay`'s real curve measured on hardware; dpi computed to pin the framing in tiles (`SDV_TILES_X`, default 15) |

### Controls

- Movement/menus: D-pad and left stick through the native Android/MonoGame path.
- A/B/X/Y, L1/R1/L2/R2, Start and Select follow the SDL GameController mapping.
- **Right stick**: independent native crosshair cursor (radial deadzone + acceleration,
  auto-hides after 2 s). Does not steal the game's native focus.
- **R3**: sends a real Android touch while the crosshair is visible; acts as a normal
  native button while it is hidden.
- **SELECT+START**: immediate exit inside the binary (`_exit(0)`) — no Mono/GL shutdown
  hangs.

### Getting the game data — **required**

This repository ships only our loader **code**, never ConcernedApe's binaries or assets.
You must own the game and supply the legit APK:

| package | version | ABI |
|---|---|---|
| `com.chucklefish.stardewvalley` | **1.6.15.3** | arm64-v8a (32-bit will not do) |

Put the `.apk` inside the port folder and launch: `tools/stardew_extract.sh` validates
that it is the right APK *before* spending minutes unpacking, then extracts
`lib/arm64-v8a/*` → `libs/` and `assets/Content/` → `assets/Content/`. It only needs
`unzip`, present on every CFW. `SDV_KEEP_APK=1` keeps the APK afterwards.

The assembly store `libassemblies.arm64-v8a.blob.so` receives small local patches
(in-game keyboard, offline save barrier, real `statvfs` disk space) — that tooling lives
in `tools/` and runs on *your* copy. Game data is ignored by Git.

### Troubleshooting

Every session writes `sdvnextos/debug.log` (previous run in `debug.prev.log`). The line
that matters is:

```
[sdv-egl] ready 640x480 driver=KMSDRM ES2 a8 d24 s8 GL='OpenGL ES 3.2 …'
```

**Black screen** → check that `GL=` contains `OpenGL ES`. If it says `Mesa` without
`ES`, the driver handed back desktop OpenGL and the shaders will not compile; the binary
already refuses that context, but the log confirms it.
**No sound** → the game plays through OpenAL; backend order lives in `alsoft.conf`
(`pipewire`, `pulse`, `alsa`). Force one with `AUDIO_DRIVER=alsa` or `AUDIO_DRIVER=pulse`.
**Camera too close/far** → `SDV_TILES_X=15` controls the framing (screen width in tiles).

All knobs are environment variables, off by default; the full list is in
[`INSTALAR.md`](INSTALAR.md) (Portuguese).

### What is in this repository

- `src/` — the ELF loader, Bionic→glibc shims, fake JNI/JavaVM, EGL/GLES bridge, fake
  asset manager and input.
- `arkos/` — the launcher (PortMaster layout, works on EmuELEC too) and `alsoft.conf`.
- `package/` — the release ZIP builder, which refuses to package a single byte of game
  data.
- `tools/` — the on-device APK extractor and the assembly-store patchers.
- `HANDOFF.md` — the full engineering log of the Mono/Xamarin bootstrap and every wall
  (required reading before touching the port).
- `stardewvalley.multi` / `stardewvalley` — prebuilt loaders (buster/GLIBC 2.17 and the
  NextOS toolchain build).

### Build

```bash
SR=<NextOS aarch64 sysroot>
docker run --rm -v "$PWD":/repo -v "$SR":/nxsr:ro \
  gtactw-arm64-builder:debian-buster bash /repo/build_buster.sh   # -> stardewvalley.multi
```

`build.sh` is the quick build with the NextOS toolchain (faster iteration, but the
binary only runs on a recent glibc). `package/build-package.sh` assembles the release
ZIP.

### Licences

The port code in this repository is © NextOS and distributed under the
**GNU GPL-3.0** (see [`LICENSE`](LICENSE)) — anyone may use, study, modify and
redistribute it under the same terms. Stardew Valley, its engine assemblies and every
asset remain the property of ConcernedApe / Chucklefish and are supplied only by the
user, from their own legal copy.

### Support this work

- 💗 **GitHub Sponsors**: [github.com/sponsors/NextOs-Ports](https://github.com/sponsors/NextOs-Ports)
- ☕ **Ko-fi**: [ko-fi.com/nextos](https://ko-fi.com/nextos)
- 🇧🇷 **PIX**: [livepix.gg/nextos](https://livepix.gg/nextos)

---

## Português

### Estado

**Jogável do início ao fim**, com save real, em dois aparelhos bem diferentes:

| Aparelho | Vídeo | Estado |
|---|---|---|
| Mali-450 / Amlogic-old (EmuELEC, fbdev) | ES2 em fbdev, 1280×720 | jogável, save real — é a bancada onde o port nasceu |
| R36S / ArkOS (RK3326, Mali-G31) | ES2 sobre contexto ES3, KMSDRM, 640×480 | jogável, save real, validado |
| Outros AArch64 (Mesa/Panfrost, wayland, muOS…) | negociado em runtime | deve subir; sem device aqui pra confirmar |

Criação de personagem, teclado interno do próprio jogo, primeiro save escrito e
validado (par de ~3 MB com `SaveGameInfo`), gameplay, áudio, VSync e RAM saudável
(~250–333 MB de RSS, sem swap relevante). O binário `stardewvalley.multi` é build
**debian:buster** (GLIBC máx. 2.17), então serve de CFW antigo até os atuais.

> O famoso "muro fundamental do allocator" (Mono abortando em `lock-free-alloc.c:608`)
> **não era muro nenhum**: Bionic e glibc numeram as constantes de `sysconf` diferente
> (`_SC_PAGESIZE` = 39 no Bionic ≠ glibc), e o Mono recebia um page size podre. Mapear
> as constantes `_SC_*` consertou o "inconsertável".

### Como funciona (arquitetura)

Não há Android, nem Java, nem sistema de Activity — fingimos os três:

1. Nosso loader ELF (`so_util`) carrega a cadeia Bionic `libmonosgen-2.0.so` →
   `libxamarin-app.so` → `libmonodroid.so`, tirando snapshot dos símbolos exportados
   entre as etapas.
2. Uma `JavaVM`/`JNIEnv` fake (vtable plana nos offsets exatos do Bionic arm64 LP64) é
   entregue ao `JNI_OnLoad`; depois o `Java_mono_android_Runtime_init` roda o bootstrap
   **completo** do .NET-for-Android (MonoVM 9.0.8.0) e retorna limpo.
3. Componentes do Mono e imagens AOT são carregados pelo `dlopen`/`dlsym` do próprio
   so-loader (o `dlopen` da glibc morre nos relocs lazy-PLT/IRELATIVE deles);
   `libaot-*.dll.so` é recusado de propósito para o Mono cair no JIT.
4. Com o runtime de pé, dirigimos o ciclo de vida da `MainActivity` na mão (`onCreate` →
   `OnCreate` gerenciado → `Game.Run()`), e a `MonoGameAndroidGameView` roda o loop
   gerenciado do jogo.
5. O SDL2 é dono do contexto ES2 real; a surface EGL10 fake só o apresenta ao MonoGame.
   O backbuffer é forçado opaco (alpha = 1) para o compositor fbdev Amlogic.
6. Áudio: XACT/OpenAL — a `libopenal32.so` do MonoGame é redirecionada para a
   `libopenal.so.1` do sistema.

Nada do aparelho está cravado: os caminhos saem de `/proc/self/exe`, e resolução, versão
de GLES, formato do backbuffer e backend de áudio são todos negociados em runtime.

### Muros vencidos

| Muro | Causa | Correção |
|---|---|---|
| asserção do allocator do Mono (`lock-free-alloc.c:608`, sgen pagesize) | numeração `_SC_*` do `sysconf` difere Bionic ≠ glibc → `mono_pagesize` podre | mapear `_SC_{39,40,96–99}` do Bionic para valores reais |
| SIGBUS no semáforo global do Mono | `sem_t` tem 16 B no Bionic vs 32 B na glibc | implementação própria de `sem_*` sobre futex |
| "No JavaVM registered with handle 0x0" (managed) | `GetJavaVM` faltando na vtable fake (slot 0x6D8) | implementar e devolver a VM fake |
| managed via exceção pendente após TODO `FindClass` | `ExceptionOccurred`/`ExceptionCheck` em offsets ERRADOS da vtable; os slots reais caíam no default não-NULL → o erro de typemap `Java.Lang.Throwable` era **sintoma** | mover pros offsets reais (idx 15 / idx 228) + `Push/PopLocalFrame` |
| SIGSEGV no `Memmove` lendo qualquer string | `Java.Interop` usa a via UTF-16 (`GetStringChars`), slots faltando → sentinel default dereferenciado | implementar os slots UTF-16 (`0x520/0x528/0x530`) |
| "JNIEnv::RegisterNatives() returned 2" | shim era `void` → managed lia lixo em `x0` | retornar `int` 0 (JNI_OK) |
| pico de ~520 MB de RAM por faixa de música | `music.xwb` de 258 MB copiado inteiro num `MemoryStream` | asset stream fake expõe só os metadados XACT e converte o descarte em `fseek` nativo |
| `SetRenderTarget` ignorado em silêncio (sem FBOs) | `Looper.myLooper()` fake fazia `SyncContext.Send` rodar na task background | promover a worker a foreground no `myLooper` — semântica de UI thread restaurada |
| Mali corrompia após ~1500 frames | wrappers temporários de trace GL | dispatch de produção devolve os entrypoints do contexto direto (14 mil+ frames estável) |
| sem teclado nos campos `TextBox` | `ShowAndroidKeyboard` espera o IME do Android | patch abre o `TextEntryMenu` interno do próprio jogo |
| save preso / "disco cheio" simulado | barreira de rede offline + `Java.IO.File.get_UsableSpace` devolvendo 0 | confirmar a barreira e devolver o `statvfs` real |
| flicker/tearing | swap interval setado antes do contexto existir | `SDL_GL_SetSwapInterval(1)` com o contexto atual |
| jogo fechava no "Salvando…" em outro aparelho | `getFilesDir` cravado no caminho de um device | tudo passa a sair de `/proc/self/exe` (`$HOME` não serve de âncora — o Mono o reescreve no `Runtime_init`) |
| zoom de celular (~13 tiles) | o `DisplayMetrics` fake reportava 160 dpi fixo | curva real do `MobileDisplay` medida no aparelho; dpi calculado pra fixar o enquadramento em tiles (`SDV_TILES_X`, padrão 15) |

### Controles

- Movimento/menus: D-pad e analógico esquerdo pelo caminho nativo Android/MonoGame.
- A/B/X/Y, L1/R1/L2/R2, Start e Select seguem o mapeamento SDL GameController.
- **Analógico direito**: cursor crosshair nativo independente (deadzone radial +
  aceleração, some sozinho após 2 s). Não rouba o foco nativo do jogo.
- **R3**: envia toque Android real enquanto o crosshair está visível; é botão nativo
  normal quando ele está oculto.
- **SELECT+START**: saída imediata no binário (`_exit(0)`) — sem travas de shutdown
  Mono/GL.

### Como obter os dados do jogo — **obrigatório**

Este repositório distribui só o **código** do nosso loader, nunca binários ou assets da
ConcernedApe. Você precisa ter o jogo e fornecer o APK legítimo:

| pacote | versão | ABI |
|---|---|---|
| `com.chucklefish.stardewvalley` | **1.6.15.3** | arm64-v8a (a de 32 bits não serve) |

Ponha o `.apk` dentro da pasta do port e abra: o `tools/stardew_extract.sh` confere que é
o APK certo *antes* de gastar minutos descompactando, e então extrai `lib/arm64-v8a/*` →
`libs/` e `assets/Content/` → `assets/Content/`. Depende só de `unzip`, presente em todo
CFW. `SDV_KEEP_APK=1` mantém o APK no fim.

O assembly store `libassemblies.arm64-v8a.blob.so` recebe pequenos patches locais
(teclado interno, barreira de save offline, espaço em disco real via `statvfs`) — esse
ferramental fica em `tools/` e roda na *sua* cópia. Os dados do jogo continuam ignorados
pelo Git.

### Se algo não funcionar

Cada sessão grava `sdvnextos/debug.log` (a anterior em `debug.prev.log`). A linha que
importa é:

```
[sdv-egl] ready 640x480 driver=KMSDRM ES2 a8 d24 s8 GL='OpenGL ES 3.2 …'
```

**Tela preta** → confira se o `GL=` contém `OpenGL ES`. Se vier `Mesa` sem `ES`, o driver
entregou OpenGL de PC e os shaders não compilam; o binário já rejeita esse contexto, mas
o log confirma.
**Sem som** → o jogo toca por OpenAL; a ordem de backends está no `alsoft.conf`
(`pipewire`, `pulse`, `alsa`). Force um com `AUDIO_DRIVER=alsa` ou `AUDIO_DRIVER=pulse`.
**Câmera muito perto ou muito longe** → `SDV_TILES_X=15` controla o enquadramento
(largura da tela em tiles).

Todos os ajustes são variáveis de ambiente, desligadas por padrão; a lista completa está
em [`INSTALAR.md`](INSTALAR.md).

### O que tem neste repositório

- `src/` — o loader ELF, os shims Bionic→glibc, a JNI/JavaVM fake, a ponte EGL/GLES, o
  asset manager fake e o input.
- `arkos/` — o launcher (layout PortMaster, serve no EmuELEC também) e o `alsoft.conf`.
- `package/` — o montador do ZIP de release, que se recusa a empacotar um byte de dado
  de jogo.
- `tools/` — o extrator de APK que roda no aparelho e os patchers do assembly store.
- `HANDOFF.md` — o log de engenharia completo do bootstrap Mono/Xamarin e de cada muro
  (leitura obrigatória antes de mexer no port).
- `stardewvalley.multi` / `stardewvalley` — loaders já compilados (buster/GLIBC 2.17 e o
  build da toolchain NextOS).

### Compilar

```bash
SR=<sysroot NextOS aarch64>
docker run --rm -v "$PWD":/repo -v "$SR":/nxsr:ro \
  gtactw-arm64-builder:debian-buster bash /repo/build_buster.sh   # -> stardewvalley.multi
```

`build.sh` é o build rápido com a toolchain do NextOS (itera mais rápido, mas o binário
só serve em glibc nova). O `package/build-package.sh` monta o ZIP da release.

### Licenças

O código do port neste repositório é © NextOS e distribuído sob a **GNU GPL-3.0** (veja
[`LICENSE`](LICENSE)) — qualquer um pode usar, estudar, modificar e redistribuir nos
mesmos termos. Stardew Valley, seus assemblies e todos os assets continuam sendo da
ConcernedApe / Chucklefish e são fornecidos apenas pelo usuário, da sua própria cópia
legal.

### Apoie este trabalho

- 💗 **GitHub Sponsors**: [github.com/sponsors/NextOs-Ports](https://github.com/sponsors/NextOs-Ports)
- ☕ **Ko-fi**: [ko-fi.com/nextos](https://ko-fi.com/nextos)
- 🇧🇷 **PIX**: [livepix.gg/nextos](https://livepix.gg/nextos)
