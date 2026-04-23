SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

VIM_BIN ?= vim

.PHONY: test test-debug list-suites list-cases help

test:
	@VIM_BIN=$(VIM_BIN) tests/run

test-debug:
	@DEBUG=1 VIM_BIN=$(VIM_BIN) tests/run

list-suites:
	@find tests/suites/shared $(if $(filter MINGW% MSYS% CYGWIN%,$(shell uname -s)),tests/suites/windows,tests/suites/unix) -maxdepth 1 -name '*.vader' -print \
		| xargs -n1 basename | sed 's/.vader$$//' | sort

list-cases:
ifndef SUITE
	$(error Usage: make list-cases SUITE=xxx)
endif
	@SUITE_FILE=$$(find tests/suites/shared $(if $(filter MINGW% MSYS% CYGWIN%,$(shell uname -s)),tests/suites/windows,tests/suites/unix) -maxdepth 1 -name '$(SUITE).vader' -print -quit); \
	if [ -z "$$SUITE_FILE" ]; then \
		echo "suite not found: $(SUITE)"; \
		exit 1; \
	fi; \
	awk '/^Execute/ {print}' "$$SUITE_FILE"

help:
	@echo "make test"
	@echo "make test SUITE=xxx"
	@echo "make test SUITE=xxx CASE=pattern"
	@echo "make test-debug"
	@echo "make list-suites"
	@echo "make list-cases SUITE=xxx"
