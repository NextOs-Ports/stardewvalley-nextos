# Stardew Valley (NextOS) — port multi-device

So-loader próprio que roda o **Stardew Valley de Android** (Mono/.NET 8 AOT + MonoGame)
direto no Linux do handheld, sem Android e sem container.

Este pacote traz **somente o nosso código**. Os dados do jogo (`assets/` e `libs/`) saem do
**seu próprio APK** — nada de jogo é distribuído aqui.

---

## Onde já roda

| Aparelho | Vídeo | Estado |
|---|---|---|
| Mali-450 / Amlogic-old (EmuELEC, fbdev) | ES2, fbdev | jogável, save real, é a bancada canônica |
| R36S / ArkOS (RK3326, Mali-G31) | ES2 sobre contexto ES3, KMSDRM | jogável, save real, validado 29/07/2026 |
| Mesa/Panfrost, wayland, outros AArch64 | negociado em runtime | deve subir; sem device pra confirmar |

O binário `stardewvalley.multi` é build **debian:buster** (GLIBC máx. 2.17), então serve de
CFW antigo (piso do ArkOS é 2.30) até os atuais. O `stardewvalley` é o build da toolchain
NextOS e fica como alternativa.

---

## Montagem no aparelho

```
<roms>/ports/Stardew Valley (NextOS).sh      <- launcher (deste zip: arkos/)
<roms>/ports/sdvnextos/
    stardewvalley.multi                      <- deste zip
    alsoft.conf                              <- deste zip (arkos/)
    tools/stardew_extract.sh                 <- deste zip
    <seu APK>.apk                            <- VOCE poe aqui, e so'
```

Abra o port uma vez: ele extrai `libs/` e `assets/Content/` do APK sozinho (~420 MB,
alguns minutos), apaga o APK pra liberar o cartão e entra no jogo. `SDV_KEEP_APK=1`
mantém o APK.

**APK necessário** — sua cópia legal:

| pacote | versão | ABI |
|---|---|---|
| `com.chucklefish.stardewvalley` | **1.6.15.3** | arm64-v8a |

O extrator confere que é o APK certo *antes* de gastar minutos descompactando, e depende só
de `unzip` (presente em todo CFW — sem aapt, python ou love2d). Se preferir fazer no PC:
`lib/arm64-v8a/*` → `libs/` e `assets/Content/` → `assets/Content/`.

O launcher acha o `<roms>` sozinho (`$directory` do PortMaster, `/roms`, `/storage/roms`, ou
o diretório do próprio script). O binário confirma pela própria localização
(`/proc/self/exe`) — não há caminho de aparelho cravado em lugar nenhum, e as libs do Mono
são procuradas tanto na raiz do port quanto em `libs/`.

---

## Se algo não funcionar num aparelho novo

Todos os escapes são variáveis de ambiente, **desligadas por padrão**. Servem pra descobrir
o que negociar; achado o acerto, ele vira automático no binário.

| Variável | Para que serve |
|---|---|
| `SDV_TILES_X=15` | enquadramento da câmera (largura em tiles). Menos = mais perto |
| `SDV_DPI=142` | crava o DPI reportado (sobrepõe o `SDV_TILES_X`) |
| `SDV_WIDTH` / `SDV_HEIGHT` | crava a resolução (a cadeia automática já cobre o normal) |
| `SDV_NO_FORCE_GLES=1` | não pedir a lib GLES/EGL (só se o aparelho já for GLES nativo) |
| `SDV_EXCL_FS=1` | fullscreen exclusivo em vez de borderless |
| `AUDIO_DRIVER=pulse\|pipewire\|alsa` | backend do OpenAL, quando ficar mudo |
| `SDV_GL_TRACE=1` | conta frames no log (`swap #N`) |

O log de cada sessão fica em `sdvnextos/debug.log` (a anterior em `debug.prev.log`). A
primeira coisa a ler é a linha `[sdv-egl] ready ... GL='...'`: ela diz com qual GPU e qual
contexto você está falando.

**Tela preta?** Confira se o `GL_VERSION` do log contém `OpenGL ES`. Se vier `Mesa` sem
`ES`, é contexto desktop e os shaders não compilam — o binário já rejeita esse contexto,
mas o log confirma.

**Mudo?** O jogo toca por OpenAL; quem negocia o backend é o `alsoft.conf`
(`drivers = pipewire,pulse,alsa`). Tente `AUDIO_DRIVER=alsa` ou `pulse`.

Sair do jogo: **SELECT + START**.

---

## Compilar

```bash
SR=<sysroot NextOS aarch64>
docker run --rm -v "$PWD":/repo -v "$SR":/nxsr:ro \
  gtactw-arm64-builder:debian-buster bash /repo/build_buster.sh
```
Gera `stardewvalley.multi`. O script confere no fim que o GLIBC máximo ficou ≤ 2.30.

`build.sh` faz o build rápido com a toolchain do NextOS (itera mais rápido, mas o binário só
serve em glibc nova).
