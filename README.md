# Shelia 🐚

Shelia is a modular shell script library designed to simplify and automate common development workflows. It provides specialized modules for Maven project management, Git operations, structured terminal logging, and more, all through a consistent bash-based API.

### How to use

To use Shelia in your scripts, source the `universe.sh` entry point from the project root:

```bash
source "/path/to/shelia/universe.sh"
```

Once sourced, all Shelia functions become available for use in your script (e.g., `shelia::logging::info`, `shelia::maven::update_maven_version`, etc.). For more granular control, you can also source individual files from the `lib/` directory.

### Example Usage

Here's a simple script showing some of Shelia's capabilities:

```bash
#!/bin/bash
source "./universe.sh"

# Use logging banners, info, and warning messages
shelia::logging::banner "Shelia Example"
shelia::logging::info "This is an informational message."
shelia::logging::warn "A potential warning for the user..."

# Use color formatting
echo -e "$(shelia::color::success "SUCCESS") - Task completed successfully."
echo -e "Check out the $(shelia::color::cyan "cyan") color utility!"

# Use Maven integration (requires mvn installed)
if command -v mvn &> /dev/null; then
  shelia::maven::resolve_maven_settings_file
  shelia::logging::info "Maven settings located at: $SHELIA_MAVEN_SETTINGS_FILE"
fi

# Use Git operations
if shelia::git::check_git_repo; then
  shelia::logging::info "Current directory is a clean Git repository."
fi
```

For more detailed examples, check out [example_usage.sh](./example_usage.sh).

