.PHONY: test lint deps

test:
	bash tests/run.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "shellcheck not found. Please install ShellCheck (e.g., 'brew install shellcheck')."; \
		exit 1; \
	}
	shellcheck lib/*.sh tests/*.sh

deps:
	@command -v brew >/dev/null 2>&1 || { \
		echo "brew not found. Please install Homebrew from https://brew.sh/"; \
		exit 1; \
	}
	brew bundle
