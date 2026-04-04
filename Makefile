.PHONY: test lint deps format format-check run

test:
	env bash tests/run.sh

# Run the example usage script or a specified script/method.
# Usage:
#   make run                          -> Run default example_usage.sh
#   make run script=path/to/script.sh -> Run a specific script
#   make run method=my_func           -> Run a function from universe.sh
#   make run script=lib.sh method=foo -> Run a function from a specific library
#   make run args="arg1 arg2"         -> Pass arguments to script or method
run:
	@if [ -n "$(method)" ]; then \
		script=$${script:-universe.sh}; \
		env bash -c "source $$script && $(method) $(args)"; \
	elif [ -n "$(script)" ]; then \
		env bash "$(script)" $(args); \
	else \
		env bash example_usage.sh $(args); \
	fi

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
