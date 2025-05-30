#!/usr/bin/env bats

# Temporary directory for logs and mocks, managed by bats
COMMANDS_LOG="$BATS_TMPDIR/commands.log"
MOCK_DIR="$BATS_TMPDIR/mock_bin"

# Path to the script under test. Assumes tests are in a 'tests' subdirectory.
SCRIPT_UNDER_TEST="../build.sh"

setup_file() {
    # Create directory for mock executables
    mkdir -p "$MOCK_DIR"
    # Ensure the log file exists and is empty before tests start
    touch "$COMMANDS_LOG"

    # Create mock pip executable
    cat > "$MOCK_DIR/pip" <<-'EOF'
#!/bin/bash
echo "pip $@" >> "$COMMANDS_LOG"
# Conditional failure for testing errexit
if [[ "$PIP_SHOULD_FAIL" == "true" && "$*" == "install -r requirements.txt" ]]; then
  exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/pip"

    # Create mock python executable
    cat > "$MOCK_DIR/python" <<-'EOF'
#!/bin/bash
if [ "$1" == "manage.py" ]; then
    echo "python $@" >> "$COMMANDS_LOG"
    # Conditional failure for testing errexit with manage.py commands
    if [[ "$PYTHON_MANAGEPY_SHOULD_FAIL" == "true" && "$2" == "collectstatic" && "$3" == "--no-input" ]]; then
      exit 1
    fi
    exit 0
elif [[ "$1" == "-m" && "$2" == "pip" ]]; then
    # Log the command as it appears in build.sh
    echo "python -m pip ${@:3}" >> "$COMMANDS_LOG"
    # Delegate to the mock pip command
    "$MOCK_DIR/pip" "${@:3}"
    exit $? # Propagate pip mock's exit status
else
    # Log any other calls to python
    echo "python $@" >> "$COMMANDS_LOG"
    exit 0
fi
EOF
    chmod +x "$MOCK_DIR/python"

    # Prepend mock directory to PATH so our mocks are found first
    export PATH="$MOCK_DIR:$PATH"
}

setup() {
    # This function runs before each test case
    # Clear the command log for a clean slate for each test
    > "$COMMANDS_LOG"
    # Reset any failure flags
    unset PIP_SHOULD_FAIL
    unset PYTHON_MANAGEPY_SHOULD_FAIL
}

@test "build.sh: runs successfully with all commands mocked" {
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 0 ]
}

@test "build.sh: upgrades pip using 'python -m pip'" {
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 0 ]
    grep -q "python -m pip install --upgrade pip" "$COMMANDS_LOG"
}

@test "build.sh: installs requirements using 'pip install'" {
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 0 ]
    grep -q "pip install -r requirements.txt" "$COMMANDS_LOG"
}

@test "build.sh: runs collectstatic" {
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 0 ]
    grep -q "python manage.py collectstatic --no-input" "$COMMANDS_LOG"
}

@test "build.sh: runs makemigrations" {
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 0 ]
    grep -q "python manage.py makemigrations" "$COMMANDS_LOG"
}

@test "build.sh: runs migrate" {
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 0 ]
    grep -q "python manage.py migrate" "$COMMANDS_LOG"
}

@test "build.sh: exits with error if 'pip install requirements' fails (due to set -o errexit)" {
    export PIP_SHOULD_FAIL="true" # Make the 'pip install -r requirements.txt' call fail
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -ne 0 ]
    grep -q "pip install -r requirements.txt" "$COMMANDS_LOG" # Ensure the failing command was attempted
    ! grep -q "python manage.py collectstatic --no-input" "$COMMANDS_LOG" # Ensure subsequent commands did not run
}

@test "build.sh: exits with error if 'collectstatic' fails (due to set -o errexit)" {
    export PYTHON_MANAGEPY_SHOULD_FAIL="true" # Make 'python manage.py collectstatic' fail
    run "$SCRIPT_UNDER_TEST"
    [ "$status" -ne 0 ]
    grep -q "python manage.py collectstatic --no-input" "$COMMANDS_LOG" # Ensure the failing command was attempted
    ! grep -q "python manage.py makemigrations" "$COMMANDS_LOG" # Ensure subsequent commands did not run
}