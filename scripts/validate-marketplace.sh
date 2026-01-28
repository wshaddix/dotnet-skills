#!/bin/bash
# Validates that plugin.json is consistent with actual skill/agent files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

errors=0
warnings=0

echo "Validating marketplace structure..."
echo ""

# Check JSON syntax
if ! jq . "$MARKETPLACE_JSON" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Invalid JSON syntax in marketplace.json${NC}"
    exit 1
fi
echo -e "${GREEN}marketplace.json syntax: OK${NC}"

if ! jq . "$PLUGIN_JSON" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Invalid JSON syntax in plugin.json${NC}"
    exit 1
fi
echo -e "${GREEN}plugin.json syntax: OK${NC}"

# Check skill references (now folders with SKILL.md)
echo ""
echo "Checking skills..."
while IFS= read -r source; do
    # Remove leading ./ if present
    clean_source="${source#./}"
    file="$REPO_ROOT/${clean_source}/SKILL.md"

    if [ ! -f "$file" ]; then
        echo -e "${RED}ERROR: Missing SKILL.md for: $source${NC}"
        echo -e "${RED}       Expected: $file${NC}"
        ((++errors))
    else
        # Extract skill name from SKILL.md frontmatter
        skill_name=$(grep "^name:" "$file" | head -1 | sed 's/^name: *//')
        echo -e "${GREEN}OK: $skill_name ($source)${NC}"
    fi
done < <(jq -r '.skills[]' "$PLUGIN_JSON")

# Check agent references
echo ""
echo "Checking agents..."
agents_value=$(jq -r '.agents' "$PLUGIN_JSON")
agents_type=$(jq -r '.agents | type' "$PLUGIN_JSON")

if [ "$agents_type" = "string" ]; then
    # agents is a directory path
    clean_dir="${agents_value#./}"
    agents_dir="$REPO_ROOT/${clean_dir}"

    if [ ! -d "$agents_dir" ]; then
        echo -e "${RED}ERROR: Missing agents directory: $agents_dir${NC}"
        ((++errors))
    else
        for file in "$agents_dir"/*.md; do
            if [ -f "$file" ]; then
                agent_name=$(grep "^name:" "$file" | head -1 | sed 's/^name: *//')
                echo -e "${GREEN}OK: $agent_name${NC}"
            fi
        done
    fi
elif [ "$agents_type" = "array" ]; then
    # agents is an array of paths
    while IFS= read -r source; do
        # Remove leading ./ if present
        clean_source="${source#./}"
        file="$REPO_ROOT/${clean_source}.md"

        if [ ! -f "$file" ]; then
            echo -e "${RED}ERROR: Missing agent file: $file${NC}"
            ((++errors))
        else
            agent_name=$(grep "^name:" "$file" | head -1 | sed 's/^name: *//')
            echo -e "${GREEN}OK: $agent_name${NC}"
        fi
    done < <(jq -r '.agents[]' "$PLUGIN_JSON")
fi

# Check for unregistered skills (find all SKILL.md files)
echo ""
echo "Checking for unregistered skills..."
while IFS= read -r file; do
    # Get the directory containing SKILL.md relative to repo root
    skill_dir=$(dirname "$file" | sed "s|$REPO_ROOT/||")
    source="./$skill_dir"

    if ! jq -e --arg src "$source" '.skills[] | select(. == $src)' "$PLUGIN_JSON" > /dev/null 2>&1; then
        echo -e "${YELLOW}WARNING: Skill not in plugin.json: $source${NC}"
        ((++warnings))
    fi
done < <(find "$REPO_ROOT/skills" -name "SKILL.md" 2>/dev/null)

# Check for unregistered agents
echo ""
echo "Checking for unregistered agents..."
if [ "$agents_type" = "string" ]; then
    # When agents is a directory, all .md files in that directory are automatically included
    echo -e "${GREEN}Using directory mode: all agents in ${agents_value} are included${NC}"
elif [ "$agents_type" = "array" ]; then
    for file in "$REPO_ROOT"/agents/*.md; do
        if [ -f "$file" ]; then
            basename=$(basename "$file" .md)
            source="./agents/$basename"
            if ! jq -e --arg src "$source" '.agents[] | select(. == $src)' "$PLUGIN_JSON" > /dev/null 2>&1; then
                echo -e "${YELLOW}WARNING: Agent file not in plugin.json: $basename${NC}"
                ((++warnings))
            fi
        fi
    done
fi

# Summary
echo ""
echo "=== Summary ==="
echo "Skills registered: $(jq '.skills | length' "$PLUGIN_JSON")"
if [ "$agents_type" = "string" ]; then
    agents_count=$(find "$agents_dir" -name "*.md" 2>/dev/null | wc -l)
    echo "Agents registered: $agents_count (directory mode: $agents_value)"
else
    echo "Agents registered: $(jq '.agents | length' "$PLUGIN_JSON")"
fi
echo "Plugin version: $(jq -r '.version' "$PLUGIN_JSON")"

if [ $errors -gt 0 ]; then
    echo -e "${RED}Errors: $errors${NC}"
    exit 1
fi

if [ $warnings -gt 0 ]; then
    echo -e "${YELLOW}Warnings: $warnings${NC}"
fi

echo -e "${GREEN}Validation passed!${NC}"
