#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$COMMAND" =~ jj\ split.*(-i|--interactive|--tool) ]] || [[ "$COMMAND" =~ jj\ split[^[:space:]]*\ -i ]]; then
  echo "BLOCKED: jj split --interactive is not supported in non-interactive mode. Use fileset-based split instead: jj split -r <rev> -m \"message\" path/to/file ..." >&2
  exit 2
fi

exit 0
