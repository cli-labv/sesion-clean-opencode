.PHONY: test lint check clean help

help:
	@echo "make test   - ejecuta los tests (DB de ejemplo)"
	@echo "make lint   - bash -n + shellcheck"
	@echo "make check  - lint + tests"
	@echo "make clean  - borra backups/ locales"

test:
	./tests/run-tests.sh

lint:
	bash -n cleanup-sessions.sh tests/run-tests.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S warning cleanup-sessions.sh tests/run-tests.sh; \
	else \
		echo "shellcheck no instalado: se omite (apt install shellcheck)"; \
	fi

check: lint test

clean:
	rm -rf backups
