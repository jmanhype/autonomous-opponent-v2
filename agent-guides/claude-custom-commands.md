# How to Add Custom Commands to Claude Code

Custom slash commands in Claude Code allow you to define frequently-used prompts as reusable commands, improving workflow efficiency and consistency.

## Command Types

### Project Commands
Commands shared with your team and stored in your repository.

**Location**: `.claude/commands/`  
**Prefix**: `/project:`

```bash
# Create a project command
mkdir -p .claude/commands
echo "Analyze this code for performance issues and suggest optimizations:" > .claude/commands/optimize.md
```

**Usage**: `/project:optimize`

### Personal Commands
Commands available across all your projects.

**Location**: `~/.claude/commands/`  
**Prefix**: `/user:`

```bash
# Create a personal command
mkdir -p ~/.claude/commands
echo "Review this code for security vulnerabilities:" > ~/.claude/commands/security-review.md
```

**Usage**: `/user:security-review`

## Advanced Features

### Namespacing
Organize commands in subdirectories to create namespaced commands.

**Structure**: `<prefix>:<namespace>:<command>`

```bash
# Creates /project:frontend:component
mkdir -p .claude/commands/frontend
echo "Create a React component following our design system:" > .claude/commands/frontend/component.md
```

### Arguments
Pass dynamic values using the `$ARGUMENTS` placeholder.

```bash
# Command definition
echo "Fix issue #$ARGUMENTS following our coding standards" > .claude/commands/fix-issue.md

# Usage
/project:fix-issue 123
```

## Command Syntax

```
/<prefix>:<command-name> [arguments]
```

- `<prefix>`: `project` or `user`
- `<command-name>`: Filename without `.md` extension
- `[arguments]`: Optional dynamic values

## File Requirements

- Use Markdown format (`.md` extension)
- Place in appropriate commands directory
- Content becomes the prompt sent to Claude

## Examples

### Code Review Command
```bash
echo "Please review this code for:
- Code quality and best practices
- Security vulnerabilities
- Performance optimizations
- Documentation completeness

Focus on: $ARGUMENTS" > .claude/commands/review.md
```

### Bug Triage Command
```bash
echo "Analyze this bug report and provide:
1. Root cause analysis
2. Severity assessment
3. Recommended fix approach
4. Testing strategy

Bug details: $ARGUMENTS" > .claude/commands/triage.md
```

### Architecture Review
```bash
mkdir -p .claude/commands/architecture
echo "Review this architectural design for:
- Scalability concerns
- Security implications
- Maintainability
- Best practices alignment

Focus area: $ARGUMENTS" > .claude/commands/architecture/review.md
```

## Best Practices

1. **Keep commands focused**: Each command should have a single, clear purpose
2. **Use descriptive names**: Command names should clearly indicate their function
3. **Leverage arguments**: Make commands flexible with `$ARGUMENTS` placeholder
4. **Organize with namespaces**: Group related commands in subdirectories
5. **Share project commands**: Commit `.claude/commands/` to version control for team consistency
6. **Document commands**: Consider adding a commands index in your project README

## Built-in Commands Reference

| Command | Purpose |
|---------|---------|
| `/help` | Get usage help |
| `/clear` | Clear conversation history |
| `/review` | Request code review |
| `/memory` | Edit CLAUDE.md memory files |
| `/cost` | Show token usage statistics |
| `/model` | Select or change AI model |

## See Also

- [Claude Code Search Best Practices](claude-code-search-best-practices.md) - Comprehensive guide to effective searching in Claude Code
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/slash-commands)
- [Interactive Mode](https://docs.anthropic.com/en/docs/claude-code/interactive-mode)
- [Memory Management](https://docs.anthropic.com/en/docs/claude-code/memory)
