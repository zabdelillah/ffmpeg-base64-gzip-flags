#!/bin/bash

# Loop through all files (modify pattern if needed)
for file in transitions/*.glsl; do
  if [ -f "$file" ]; then
    # Check if file contains a line matching the pattern
    # Pattern: #define
    if grep -Eq '^#define\s+[A-Za-z_][A-Za-z0-9_]*\s+[0-9]*\.?[0-9]+' "$file"; then
      matched_line=$(grep -E '^#define\s+[A-Za-z_][A-Za-z0-9_]*\s+[0-9]*\.?[0-9]+' "$file" | head -n1)

      # Extract variable name (macro)
      var=$(echo "$matched_line" | grep -Eo '^#define\s+[A-Za-z_][A-Za-z0-9_]*' | awk '{print $2}')

      # Extract numeric value as is (full decimal), stopping before any comment. Avoid grep -Eo which cuts early.
      val=$(echo "$matched_line" | sed -E 's/^#define\s+[A-Za-z_][A-Za-z0-9_]*\s+([0-9]+\.[0-9]+).*/\1/')

      # Escape slashes in matched line for safe sed deletion
      escaped_line=$(printf '%s\n' "$matched_line" | sed 's/[\\/&]/\\&/g')

      # Delete the exact matched #define line
      sed -i.bak "\|^#define.*$|d" "$file"

      # Replace all exact word matches of variable name with numeric value (no parentheses)
      sed -i.bak "s/\b${var}\b/${val}/g" "$file"

      echo "File: $file, Variable: $var, Value: $val, DEF"
    fi

    # Pattern: ^uniform <type> <var>; // = <value>
    if grep -Eq '^uniform.*//\s.*[0-9]+$' "$file"; then
      # Extract the line
      # matched_line=$(grep -E '^uniform.*[0-9]+$' "$file" | head -n1)
      grep -E '^uniform.*[0-9]+$' "$file" | while read -r matched_line; do

        # Extract variable and value using sed or bash param expansion
        # The line looks like: uniform float size; // = 0.2
        var=$(echo "$matched_line" | grep -Eo '^uniform\s+[a-zA-Z]+\s+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $3}')
        val=$(echo "$matched_line" | grep -Eo '[0-9\.]+$')

        echo "File: $file, Variable: $var, Value: $val"

        # # Remove the line from the file
        sed -i.bak "\|${matched_line}|d" "$file"
        sed -i.bak "s/${var}/\(${val}\)/g" "$file"
        # sed -i.bak "/^uniform\s\+\S\+\s\+$var;\s*\/\/\s*=\s*$val$/d" "$file"

        # # Replace all occurrences of the variable with the value
        # # Using word boundaries to avoid partial matches (e.g., sizeX)
        # sed -i.bak "s/\b$var\b/$val/g" "$file"

        # # Optionally remove the .bak file if you don't need backup
        # rm "${file}.bak"
      done
    fi
  fi
done
