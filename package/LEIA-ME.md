# Stardew Valley (NextOS) — como instalar

Port do **Stardew Valley de Android** rodando direto no Linux do seu portátil, por um
so-loader próprio: sem Android, sem emulador, sem container.

Este pacote traz **só o programa**. Os dados do jogo saem do **seu APK** — nada de conteúdo
do jogo é distribuído aqui.

---

## 1. Copie os arquivos

O zip já está no formato do aparelho: **extraia na raiz da sua pasta de ROMs** e pronto.

| Sistema | Extraia em |
|---|---|
| ArkOS, ROCKNIX, muOS, Knulli, batocera | `/roms` |
| EmuELEC / NextOS | `/storage/roms` |

Fica assim:

```
roms/ports/Stardew Valley (NextOS).sh
roms/ports/sdvnextos/…
roms/ports_scripts/Stardew Valley (NextOS).sh
```

> As duas cópias do launcher são de propósito: o EmulationStation do EmuELEC/NextOS lê de
> `ports_scripts/`, e o ArkOS/ROCKNIX/PortMaster lê de `ports/`. Deixe as duas — quem não
> usa uma, ignora.

A pasta `fonte/` é só para quem quiser compilar; **não precisa ir para o aparelho**.

## 2. Ponha o seu APK

Copie o APK do jogo para dentro de `roms/ports/sdvnextos/`:

| pacote | versão | ABI |
|---|---|---|
| `com.chucklefish.stardewvalley` | **1.6.15.3** | arm64-v8a |

Precisa ser **arm64-v8a** — a versão de 32 bits não serve.

## 3. Abra pelo menu de Ports

Na primeira vez ele extrai os dados do APK sozinho (~420 MB, alguns minutos, a tela mostra
o progresso), apaga o APK para liberar o cartão e entra no jogo. Da segunda em diante abre
direto.

**Sair do jogo: SELECT + START.**

---

## Onde já foi testado

| Aparelho | Estado |
|---|---|
| Mali-450 / Amlogic (EmuELEC) | jogável, save real — é a bancada onde o port nasceu |
| R36S / ArkOS (RK3326, Mali-G31) | jogável, save real, validado |
| Outros AArch64 (Mesa/Panfrost, wayland, muOS…) | deve funcionar — o port negocia vídeo e áudio sozinho, mas ainda não foi confirmado em campo |

O binário roda de glibc 2.17 pra cima, então serve tanto em CFW antigo quanto atual.

---

## Se der problema

Todo o diagnóstico está em `sdvnextos/debug.log` (a sessão anterior fica em
`debug.prev.log`). A linha mais importante é esta:

```
[sdv-egl] ready 640x480 driver=KMSDRM ES2 a8 d24 s8 GL='OpenGL ES 3.2 …'
```

Ela diz a resolução, o backend de vídeo e **com qual GPU** você está falando.

**Tela preta** → veja se o `GL=` contém `OpenGL ES`. Se aparecer `Mesa` sem `ES`, o driver
entregou OpenGL de PC e os shaders não compilam; o port já recusa esse contexto sozinho,
mas o log confirma.

**Sem som** → o jogo toca por OpenAL e a ordem de backends está em `alsoft.conf`
(`pipewire`, depois `pulse`, depois `alsa`). Force um com `AUDIO_DRIVER=alsa` ou
`AUDIO_DRIVER=pulse`.

**Câmera muito perto ou muito longe** → `SDV_TILES_X=15` controla o enquadramento (quantos
quadrados de largura aparecem). Menos = mais perto.

Os ajustes são variáveis de ambiente, todas desligadas por padrão. A lista completa está em
`sdvnextos/INSTALAR.md`.

---

## Créditos e licença

Port por **NextOS Ports**. O jogo é da Chucklefish/ConcernedApe — este pacote
não distribui nem redistribui conteúdo dele; você usa a sua própria cópia.
