.PHONY: test lint install uninstall

test:
	./tests/run.sh

lint:
	shellcheck --severity=warning -s sh bin/tmux-start.sh
	shellcheck --severity=warning bin/opencode-clean.sh install.sh uninstall.sh

install:
	./install.sh

uninstall:
	./uninstall.sh
