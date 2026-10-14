.PHONY: install install-notify uninstall-notify up down restart logs ps bench

# Install location; overridden by config.mk inside an installed copy
DOCKER_DIR ?= /docker
PROJECT    ?= whisper
-include config.mk

TARGET := $(DOCKER_DIR)/$(PROJECT)
FILES  := docker-compose.yml Dockerfile.watcher watcher.sh notify.sh whisper-notify.service Makefile README.md
DC     := docker compose --project-directory $(TARGET) -f $(TARGET)/docker-compose.yml

UNIT_DIR := $(HOME)/.config/systemd/user
UNIT     := whisper-notify.service

API  := http://127.0.0.1:9000
AUTH := -H 'Authorization: Bearer none'

# make bench BENCH_FILE=sample.mp3 BENCH_THREADS="6 8" BENCH_MODEL=medium
BENCH_FILE    ?= bench.wav
BENCH_THREADS ?= 4 6 8 14
BENCH_BEAM    ?= 1
BENCH_MODEL   ?= large-v3-turbo
BENCH_RUNS    ?= 2

# Copy the template to $(TARGET); config is overwritten, input/output/data are kept
install:
	@test "$(CURDIR)" != "$(abspath $(TARGET))" || { echo "Already in $(TARGET); run install from the template"; exit 1; }
	mkdir -p $(TARGET)/input $(TARGET)/output $(TARGET)/data
	cp $(FILES) $(TARGET)/
	chmod +x $(TARGET)/notify.sh
	printf 'DOCKER_DIR := %s\nPROJECT    := %s\n' '$(DOCKER_DIR)' '$(PROJECT)' > $(TARGET)/config.mk
	@echo "Installed to $(TARGET)"

# Desktop notifications: systemd --user service running $(TARGET)/notify.sh
install-notify:
	@test -f $(TARGET)/notify.sh || { echo "$(TARGET) is not installed; run make install"; exit 1; }
	mkdir -p $(UNIT_DIR)
	sed 's|@TARGET@|$(TARGET)|g' $(TARGET)/$(UNIT) > $(UNIT_DIR)/$(UNIT)
	systemctl --user daemon-reload
	systemctl --user enable $(UNIT)
	systemctl --user restart $(UNIT)

uninstall-notify:
	-systemctl --user disable --now $(UNIT)
	rm -f $(UNIT_DIR)/$(UNIT)
	systemctl --user daemon-reload

up:
	@test -f $(TARGET)/docker-compose.yml || { echo "$(TARGET) is not installed; run make install"; exit 1; }
	$(DC) up -d --build

down:
	$(DC) down

restart: down up

logs:
	$(DC) logs -f

ps:
	$(DC) ps

bench:
	@test -f "$(BENCH_FILE)" || { echo "$(BENCH_FILE) not found; set BENCH_FILE=path/to/audio"; exit 1; }
	@for t in $(BENCH_THREADS); do \
	  WHISPER_THREADS=$$t WHISPER_BEAM=$(BENCH_BEAM) WHISPER_MODEL=$(BENCH_MODEL) \
	    $(DC) up -d --force-recreate whisper >/dev/null 2>&1; \
	  until curl -sf $(AUTH) $(API)/v1/models >/dev/null; do sleep 2; done; \
	  for r in $$(seq $(BENCH_RUNS)); do \
	    s=$$(date +%s.%N); \
	    curl -sf $(AUTH) -F "file=@$(BENCH_FILE)" -F response_format=text \
	      $(API)/v1/audio/transcriptions >/dev/null || echo "request failed"; \
	    e=$$(date +%s.%N); \
	    awk -v s=$$s -v e=$$e -v t=$$t -v r=$$r 'BEGIN { printf "model=$(BENCH_MODEL) beam=$(BENCH_BEAM) threads=%-3s run=%s  %7.1f s\n", t, r, e - s }'; \
	  done; \
	done
	@echo "Restoring whisper to docker-compose.yml settings"
	@$(DC) up -d --force-recreate whisper >/dev/null 2>&1
