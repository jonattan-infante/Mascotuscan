.DEFAULT_GOAL := help
SHELL := /bin/bash
PREFIX ?= $(HOME)/.mascotuscan
BIN := $(PREFIX)/bin/mascotuscan

.PHONY: help build release test test-shell test-windows packs packs-remote render verify install uninstall run stop restart log clean fmt pr merge tag next-version release-notes

# Este repo es personal. La cuenta activa de gh es estado global que cualquier
# otra sesion voltea, asi que el token se pide explicitamente por usuario en vez
# de confiar en cual quedo activa.
GH := GH_TOKEN=$(shell gh auth token --user jonattan-infante 2>/dev/null) gh

help: ## Muestra estos comandos
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[1m%-12s\033[0m %s\n",$$1,$$2}'

build: ## Compila en modo debug
	swift build

release: ## Compila optimizado
	swift build -c release

test: ## Tests de la logica pura (Swift)
	swift test

test-shell: ## Tests de shell, instalador, integridad y mascotas
	./scripts/test-shell-hooks.sh
	./scripts/test-installer.sh
	./scripts/test-repo-integrity.sh
	./scripts/test-pet-packs.sh
	./scripts/test-release-tooling.sh

test-windows: ## Tests del port de Windows (logica pura, corre en cualquier Python 3)
	cd windows && /usr/bin/python3 -m unittest discover -s tests -p "test_*.py"

packs: ## Valida las mascotas del repo y el indice del marketplace
	./scripts/test-pet-packs.sh

packs-remote: ## Igual, pero tambien clona y valida las mascotas de terceros
	./scripts/test-pet-packs.sh --remote

render: ## Dibuja cada estado a PNG en ./render para revisarlo a ojo
	swift build && ./.build/debug/mascotuscan --render ./render
	@echo "abre ./render/todos.png y ./render/panel.png"

verify: build test test-shell test-windows ## El gate completo: lo que CI corre
	@echo ""
	@echo "verificacion completa: compila, tests de logica, hooks de zsh,"
	@echo "instalador, integridad del repo, mascotas del marketplace y port de Windows"

install: release ## Instala en ~/.mascotuscan y engancha el shell
	./install.sh --from-source

uninstall: ## Quita el asistente y su enganche del shell
	./install.sh --uninstall

run: ## Arranca el asistente en primer plano (Ctrl-C para salir)
	swift build && ./.build/debug/mascotuscan

stop: ## Detiene el asistente
	-pkill -f 'mascotuscan' 2>/dev/null || true

restart: stop ## Reinstala el binario y reinicia
	@sleep 1
	$(MAKE) install
	@echo "abre una terminal nueva de cmux para que arranque"

log: ## Sigue el log en vivo
	tail -f $(PREFIX)/pet.log

fmt: ## Formatea el Swift (requiere swift-format)
	@command -v swift-format >/dev/null && swift-format -i -r Sources Tests || echo "swift-format no instalado, omitido"

# La @ es obligatoria: sin ella make imprime la linea y el token queda en pantalla.
pr: verify ## Abre un PR de la rama actual con la cuenta correcta
	@$(GH) pr create --fill --head "$$(git branch --show-current)"
	@echo "  auto-merge:  make merge"

merge: ## Deja la rama actual en auto-merge (entra sola cuando CI pase)
	@$(GH) pr merge --auto --squash "$$(git branch --show-current)"

# Publicar es un tag, y el tag tiene reglas (docs/reference/tags.md): anotado,
# firmado, con las notas del CHANGELOG en el mensaje, desde main al dia. Se
# verifica todo ANTES de empujar; un tag empujado ya no se mueve.
GH_WEB := https://github.com/jonattan-infante/mascotuscan

next-version: ## Propone la proxima version a partir de los commits desde el ultimo tag
	@./scripts/next-version.sh

release-notes: ## Borrador de la seccion del CHANGELOG para la proxima version
	@./scripts/release-notes.sh

tag: ## Publica la version de VERSION: tag anotado y firmado desde main al dia; CI crea el release
	@test "$$(git branch --show-current)" = main || { echo "solo desde main"; exit 1; }
	@git fetch origin --quiet --tags
	@test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || { echo "main no esta al dia con origin/main"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "hay cambios sin commit"; exit 1; }
	@v="$$(tr -d '[:space:]' < VERSION)"; \
	  git rev-parse -q --verify "refs/tags/v$$v" >/dev/null && { echo "v$$v ya existe: los tags no se mueven; sube la version"; exit 1; }; \
	  { echo "mascotuscan $$v"; echo; ./scripts/changelog-section.sh "$$v"; } > .git/TAG_MSG || exit 1; \
	  git tag -s "v$$v" -F .git/TAG_MSG || { echo "no pude firmar: configura la firma, ver docs/reference/tags.md"; exit 1; }; \
	  ./scripts/check-tag.sh "v$$v" --on origin/main || { git tag -d "v$$v" >/dev/null; echo "tag borrado en local; no se empujo nada"; exit 1; }; \
	  git push origin "v$$v" && \
	  echo "v$$v empujado; el release lo crea CI: $(GH_WEB)/actions"

clean: ## Borra artefactos de build
	rm -rf .build render
