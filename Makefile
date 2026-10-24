SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

VIM_BIN ?= vim

.PHONY: setup test test-debug test-runner test-all list-suites list-cases help

setup:
	@tests/setup

test:
	@VIM_BIN=$(VIM_BIN) tests/run

test-debug:
	@DEBUG=1 KEEP_TMP=1 VIM_BIN=$(VIM_BIN) tests/run

test-runner:
	@tests/runner_contract.bash

test-all: test-runner test

list-suites:
	@tests/run --list-suites

list-cases:
ifndef SUITE
	$(error Usage: make list-cases SUITE=xxx)
endif
	@SUITE= CASE= tests/run --list-cases "$(SUITE)"

help:
	@echo "make setup"
	@echo "make test"
	@echo "make test SUITE=xxx"
	@echo "make test SUITE=xxx CASE=pattern"
	@echo "make test-debug"
	@echo "make test-runner"
	@echo "make test-all"
	@echo "make list-suites"
	@echo "make list-cases SUITE=xxx"
