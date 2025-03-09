#!/usr/bin/env bash

# This script is used to generate a command that can be used to apply a diff
# The diff is passed to this script via stdin
# The generated command is printed to stdout

# Start the command
printf '%b' 'printf %b $'"'"

# Process input one byte at a time
while IFS= read -r -d '' -n1 char || [[ -n "$char" ]]; do
    # Get ASCII value
    LC_CTYPE=C printf -v ord "%d" "'$char"

    # Handle different character types
    if [[ "$char" == '\' ]]; then
        # Escape backslashes
        printf '%s' '\\\\'
    elif [[ "$ord" -eq 9 ]]; then
        # Tab character
        printf '%s' '\\t'
    elif [[ "$ord" -eq 10 ]]; then
        # Newline (encode this literally)
        printf '%s' "$char"
    elif [[ "$ord" -eq 13 ]]; then
        # Carriage return
        printf '%s' '\\r'
    elif [[ "$ord" -eq 12 ]]; then
        # Form feed
        printf '%s' '\\f'
    elif [[ "$ord" -eq 8 ]]; then
        # Backspace
        printf '%s' '\\b'
    elif [[ "$ord" -eq 7 ]]; then
        # Alert/Bell
        printf '%s' '\\a'
    elif [[ "$ord" -eq 27 ]]; then
        # Escape
        printf '%s' '\\e'
    elif [[ "$ord" -ge 32 && "$ord" -le 126 ]]; then
        # Printable characters are kept as-is
        printf '%s' "$char"
    else
        # Encode other characters as \xHH
        printf '\\\\x%02x' "$ord"
    fi
done

# Close the command
printf '%b' "'"' | git apply -\n'
