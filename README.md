# Local STT

Offline speech-to-text for the desktop. Drop audio files into a folder and get plain-text transcripts back, with progress shown as desktop notifications. Everything runs locally on CPU via [faster-whisper](https://github.com/SYSTRAN/faster-whisper) ([hwdsl2/whisper-server](https://github.com/hwdsl2/docker-whisper)).

This directory is a **template**. `make install` deploys it to `$(DOCKER_DIR)/$(PROJECT)` (default `/docker/whisper`), and the stack runs from there.

## Requirements

### Core

| Requirement | Notes |
|---|---|
| Linux, x86_64 or arm64 | The server image is multi-arch. macOS and Windows (Docker Desktop) are untested: inotify events on bind mounts may not arrive reliably there, and notifications are Linux-only. |
| Docker Engine + Compose v2 | Uses the `docker compose` plugin. Your user must be in the `docker` group. |
| GNU make, curl | `curl` is only needed on the host for `make bench`. |
| CPU with AVX2 | Recommended for CTranslate2 int8 inference. |
| ~3 GB free RAM, ~2 GB disk | For `large-v3-turbo` (model cache plus images). Smaller models need less. |
| Internet on first start | Needed to download the model; later starts run offline from `data/`. |

An NVIDIA GPU is optional. The image ships a `:cuda` tag, but this template does not use it.

### Notifications (optional)

| Requirement | Notes |
|---|---|
| systemd user session | The service is bound to `graphical-session.target`. |
| `notify-send` (libnotify ≥ 0.7.9) | Needs `-p`/`-r` to update a single notification in place. |
| bash, coreutils, awk | Used by `notify.sh`. |
| Notification server with body markup | Renders the bold and italic text. |

| Desktop | Status |
|---|---|
| KDE Plasma 6 | Tested (NixOS). |
| GNOME, Xfce (xfce4-notifyd), dunst, mako | Expected to work: all of them support replace-id and `<b>`/`<i>` markup. |
| sway, i3, Hyprland without systemd integration | `graphical-session.target` is never reached. Start `notify.sh` from the WM's autostart instead. |
| Non-systemd distros (Alpine, Void, Gentoo/OpenRC) | Same as above: run `notify.sh` from your session autostart. |
| Ubuntu < 22.04, Debian < 12 | libnotify is too old (no `-p`). |

## How it works

```
input/ ──► watcher ──HTTP──► whisper server ──► output/<name>.txt
              │                                  output/<name>.<ext>
              └──► output/.events ──► notify.sh ──► desktop notification
```

| Component | Runs in | Role |
|---|---|---|
| `whisper` | container | OpenAI-compatible transcription API on `127.0.0.1:9000` |
| `watcher` | container | Watches `input/`, transcribes files one at a time, moves results to `output/` |
| `notify.sh` | host (systemd user service) | Turns watcher events into a single, continuously updated notification |

## Quick start

```sh
make install          # deploy to /docker/whisper
make up               # build and start; first start downloads the model (~1.6 GB)
make install-notify   # optional: desktop notifications
```

Copy audio (`mp3 wav m4a mp4 flac ogg`) into `/docker/whisper/input/`. Once a file has been transcribed, the transcript and the original audio are both moved to `output/`.

## Layout after install

| Path | Contents |
|---|---|
| `input/` | Queue. Failed files stay here and are retried when the watcher restarts. |
| `output/` | Transcripts (`.txt`) and processed audio. |
| `data/` | Model cache. Owned by root, kept across reinstalls. |
| `config.mk` | Install location, written by `make install`. |

## Make targets

| Target | Description |
|---|---|
| `install` | Copy the template to the target dir. Config files are overwritten; `input/`, `output/` and `data/` are kept. |
| `up` / `down` / `restart` | Start, stop or restart the stack. |
| `logs` / `ps` | Follow logs or show container status. |
| `install-notify` / `uninstall-notify` | Enable or remove the `whisper-notify` systemd user service. |
| `bench` | Time transcription across thread counts (see below). |

Every target except `install` works both from the template and from the installed copy. Override the location with `make install DOCKER_DIR=/srv PROJECT=stt`.

## Configuration

Set in `docker-compose.yml`. Values marked * can also be overridden through the environment.

| Variable | Default | Notes |
|---|---|---|
| `WHISPER_MODEL`* | `large-v3-turbo` | Also `medium`, `large-v3`, `small`, … |
| `WHISPER_LANGUAGE` | `cs` | Language code, or `auto`. |
| `WHISPER_THREADS`* | `6` | Best set to the number of performance cores. |
| `WHISPER_BEAM`* | `1` | Greedy decoding. Higher is slower and slightly more accurate. |

For all server options, see the [image documentation](https://github.com/hwdsl2/docker-whisper).

### Tuning

```sh
make bench BENCH_FILE=sample.mp3                      # threads 4 6 8 14
make bench BENCH_FILE=sample.mp3 BENCH_MODEL=medium BENCH_THREADS="6 8"
```

`bench` recreates the server once per setting and restores the configured values when it finishes. Copy the fastest thread count into `docker-compose.yml`.

## Notifications

The notification reads `output/.events` and updates in place. When one file finishes and the next starts straight away, both appear in the same message. Long file names are shortened. Tunables live at the top of `notify.sh`: `MERGE_WINDOW` and `NAME_MAX`.

Requires `notify-send` (libnotify ≥ 0.7.9) and a freedesktop notification server; tested on KDE Plasma 6. The unit's `PATH` targets NixOS. Adjust `whisper-notify.service` on other distros.

## Notes

- Files are transcribed one at a time on purpose, because parallel requests would just compete for the CPU.
- Restarting the watcher while it is transcribing restarts the current file from scratch.
- Do not run `make install` while the queue is being processed. It overwrites `watcher.sh`, which the running shell is still reading.
- Throughput reference: a 55 MB MP3 takes about 6 minutes on a Core Ultra 7 255H (6 threads, beam 1, `large-v3-turbo`).
