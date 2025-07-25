#!/bin/bash

# Loop through all files (modify pattern if needed)
for file in gl-transitions/transitions/*.glsl; do
  if [ -f "$file" ]; then
    # Check if file contains a line matching the pattern
    # Pattern: ^uniform <type> <var>; // = <value>
    if grep -Eq '^uniform.*//\s.*[0-9]+$' "$file"; then
      # Extract the line
      matched_line=$(grep -E '^uniform.*[0-9]+$' "$file" | head -n1)

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
      rm "${file}.bak"
    fi
  fi
done
