# Local STT

**Private, offline speech-to-text for the desktop.** Drop audio files into a folder and get readable text transcripts back. No cloud, no account, nothing leaves your machine.

1. [What it is](#what-it-is)
2. [Modules](#modules)
3. [Deployment](#deployment)
4. [Usage](#usage)
5. [Configuration](#configuration)
6. [Reference](#reference)
7. [Notes](#notes)

---

## What it is

Local STT turns recordings such as meetings, interviews, voice notes or dictation into text, entirely on your own hardware. It is built for unattended batch work: copy files in, leave it running, and collect the transcripts later.

Transcription runs on the CPU in Docker, using [faster-whisper](https://github.com/SYSTRAN/faster-whisper) via [hwdsl2/whisper-server](https://github.com/hwdsl2/docker-whisper). The defaults favour accuracy for Czech: the `large-v3` model with beam search and a style prompt. Internet access is needed only to download the model once.

```
input/ ──► watcher ──► whisper server ──► output/<name>.json ──format.jq──► output/<name>.txt
              │                            output/<name>.<audio>
              └──► output/.events ─┬─► notify.sh ──► popup notification
                                   └─► status.sh ──► tray widget
```

This directory is a **template**. `make install` deploys a self-contained copy to `/docker/whisper`, and the stack runs from there.

---

## Modules

| Module | What it does | Runs as | Required |
|---|---|---|---|
| **Core** | `whisper` server (API on `127.0.0.1:9000`) and `watcher` that processes `input/` one file at a time | Docker containers | yes |
| **Notifications** | A single popup that updates in place: file started (name, size, queue), file finished (sizes, duration), failures | `notify.sh`, systemd user service | no |
| **Tray widget** | A KDE tray icon, visible only while transcribing. The tooltip shows file, elapsed time, ETA, queue, CPU and RAM; clicking opens the output folder | `status.sh` + Plasma applet | no |

The two desktop modules are independent: install both, one, or neither. They only read `output/.events` and never affect transcription.

### Requirements

| Module | Needs |
|---|---|
| Core | Linux (x86_64/arm64), Docker Engine with Compose v2 (user in the `docker` group), GNU make. CPU with AVX2 recommended; ~6 GB free RAM and ~4 GB disk for `large-v3`. |
| Notifications | A systemd user session (`graphical-session.target`), `notify-send` from libnotify ≥ 0.7.9, and a notification server with body markup. |
| Tray widget | KDE Plasma 6, `jq`, and `docker` CLI access (for CPU/RAM; progress works without it). |

**Notification compatibility.** Tested on KDE Plasma 6 (NixOS). GNOME, Xfce, dunst and mako are expected to work. On sway, i3 or Hyprland without systemd integration, and on non-systemd distros, start `notify.sh` from your session autostart instead. Not supported on Ubuntu < 22.04 or Debian < 12, whose libnotify is too old. macOS and Windows are untested.

---

## Deployment

### Install

```sh
make install          # copy the template to /docker/whisper
make up               # build and start; the first start downloads the model (~3 GB)
make install-notify   # optional: notifications module
make install-widget   # optional: tray widget module (reloads the Plasma panel)
```

To deploy elsewhere, run `make install DOCKER_DIR=/srv PROJECT=stt`, then rerun the module targets.

### Update

Edit the template, then run `make install` and `make restart`. Do this only while the queue is idle: `make install` overwrites `watcher.sh`, which the running watcher is still reading.

### Uninstall

```sh
make uninstall-widget uninstall-notify down
sudo rm -r /docker/whisper     # data/ is owned by root
```

---

## Usage

1. Copy audio (`mp3 wav m4a mp4 flac ogg`) into `/docker/whisper/input/`.
2. Files are transcribed in turn. When a file is done, its audio, `<name>.txt` and `<name>.json` are in `output/`.
3. A file that fails stays in `input/` and is retried on the next `make restart`.

Follow progress in the desktop modules, with `make logs`, or with `./status.sh | jq`.

### Transcript format

Paragraphs are split at pauses of `PARAGRAPH_GAP` seconds or more (otherwise after roughly 500 characters), and each paragraph starts with a timestamp:

```
[00:00:01]
Good morning, so we're all here. Let's start with what we didn't finish last time.

[00:00:14]
Agreed. I have the notes here.
```

With diarization enabled, blocks become speaker turns (`[00:00:01] Speaker 1:`), and a pause within a turn only starts a new line.

The `.json` file holds the raw response, so a transcript can be reformatted without transcribing it again:

```sh
jq -r -f format.jq --arg label Speaker --argjson gap 3 output/<name>.json > output/<name>.txt
```

---

## Configuration

These are set in `docker-compose.yml`. Values marked * can also be overridden through the environment.

| Variable | Default | Notes |
|---|---|---|
| `WHISPER_MODEL`* | `large-v3` | `large-v3-turbo` with beam 1 is ~5× faster but noticeably less accurate for Czech. |
| `WHISPER_LANGUAGE` | `cs` | Language code, or `auto`. |
| `WHISPER_THREADS`* | `6` | Best set to the number of performance cores (see `make bench`). |
| `WHISPER_BEAM`* | `5` | `1` is greedy decoding: faster, with more errors. |
| `WHISPER_PROMPT` | Czech sample sentence | Style hint for punctuation, spelling and names. Write it as example text, not as instructions. |
| `WHISPER_MAX_UPLOAD_MB` | `4096` | The image default (1024) rejects long recordings. |
| `WHISPER_DIARIZATION`* | `false` | Speaker labels; see [Notes](#notes). |
| `WHISPER_DIARIZE_NUM_SPEAKERS`* | `-1` | `-1` means auto. Set the exact count when diarization is on. |
| `SPEAKER_LABEL` / `PARAGRAPH_GAP` | `Speaker` / `3` | Transcript formatting. |

For all server options, see the [image documentation](https://github.com/hwdsl2/docker-whisper).

Find the fastest thread count with `make bench BENCH_FILE=sample.mp3` (optionally `BENCH_THREADS="6 8"` or `BENCH_MODEL=…`).

---

## Reference

### Make targets

| Target | Description |
|---|---|
| `install` | Copy the template to the target directory. `input/`, `output/` and `data/` are kept. |
| `up` / `down` / `restart` | Start, stop or restart the stack. |
| `logs` / `ps` | Follow logs or show container status. |
| `install-notify` / `uninstall-notify` | Notifications module. |
| `install-widget` / `uninstall-widget` | Tray widget module. |
| `bench` | Time transcription across thread counts. |

Every target except `install` works both from the template and from the installed copy.

### Files

| Path | Purpose |
|---|---|
| `docker-compose.yml`, `Dockerfile.watcher` | Core services; the watcher image is Alpine with `inotify-tools`, `curl` and `jq`. |
| `watcher.sh`, `format.jq` | Queue processing, progress events and transcript formatting. |
| `notify.sh`, `whisper-notify.service` | Notifications module. |
| `status.sh`, `widget/` | Tray widget module. |
| `input/`, `output/`, `data/` | Created on install: queue, results (plus the `.events` log), and model cache. |
| `config.mk` | Install location, written by `make install`. |

---

## Notes

- **Speed.** On a Core Ultra 7 255H (6 threads), the same 55 MB MP3 took about 30 minutes with `large-v3` and beam 5, versus about 6 minutes with `large-v3-turbo` and beam 1. Files are processed one at a time on purpose.
- **Accuracy.** In a test on a noisy Czech conversation, `large-v3` with beam 5 and a prompt was clearly best and almost free of hallucinations. Audio quality still matters more than any setting.
- **Diarization** is off by default. On noisy, informal recordings, automatic mode split one conversation into dozens of "speakers", and it added about 45 s per 5 minutes of audio. If you enable it, set the exact number of speakers.
- **Memory.** The server decodes the whole file into RAM: about 230 MB per hour of audio, on top of the model.
- **Is it stuck?** Sustained CPU load in the tray tooltip or in `docker stats whisper` means it is working. At the start of a large file, load can stay at a single core for a while.
- **HTTP 413** means the file is larger than `WHISPER_MAX_UPLOAD_MB`.
- **Restarting the watcher** mid-file restarts that file from scratch.
