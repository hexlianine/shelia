.PHONY: test lint deps format format-check

test:
	env bash tests/run.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "shellcheck not found. Please install ShellCheck (e.g., 'brew install shellcheck')."; \
		exit 1; \
	}
	shellcheck lib/*.sh tests/*.sh

format:
	@command -v shfmt >/dev/null 2>&1 || { \
		echo "shfmt not found. Please install shfmt (e.g., 'brew install shfmt')."; \
		exit 1; \
	}
	shfmt -i 2 -w lib/*.sh tests/*.sh universe.sh example_usage.sh

format-check:
	@command -v shfmt >/dev/null 2>&1 || { \
		echo "shfmt not found. Please install shfmt (e.g., 'brew install shfmt')."; \
		exit 1; \
	}
	shfmt -i 2 -d lib/*.sh tests/*.sh universe.sh example_usage.sh

deps:
	@command -v brew >/dev/null 2>&1 || { \
		echo "brew not found. Please install Homebrew from https://brew.sh/"; \
		exit 1; \
	}
	brew bundle
