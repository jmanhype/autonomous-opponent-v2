# Agent Guides

Comprehensive guides and tools for Claude Code workflows, custom commands, and AI-assisted development.

## Contents

### 📚 Guides
- [Claude Code Custom Commands Guide](claude-custom-commands.md) - Complete guide to creating and using custom slash commands
- [Claude Code Search Best Practices](claude-code-search-best-practices.md) - Comprehensive guide to effective searching in Claude Code
- [Claude Conversation Search Guide](claude-conversation-search-guide.md) - Complete guide to searching your conversation history

### 🛠️ Ready-to-Use Tools
- [Claude Code Commands Collection](claude-commands/) - Production-ready custom commands including:
  - **Conversation Search**: Multi-source search across all your Claude conversation history
  - **Multi-Mind Analysis**: Collaborative multi-specialist analysis with dynamic role assignment
  - **Function Deep Dive**: Line-by-line code analysis with performance insights
  - **Anti-Repetition Workflows**: Progressive knowledge building across multiple rounds

## Quick Start

### Install Custom Commands

**For specific projects:**
```bash
# Copy to your project
mkdir -p .claude/commands
cp claude-commands/*.md .claude/commands/
```

**For global use:**
```bash
# Copy to global Claude directory
mkdir -p ~/.claude/commands  
cp claude-commands/*.md ~/.claude/commands/
```

### Featured Commands

#### Multi-Mind Collaborative Analysis
```bash
# Basic multi-specialist analysis (3 rounds)
/project:multi-mind "Should we implement quantum error correction in our ML pipeline?"

# Extended analysis with custom rounds
/project:multi-mind "Climate change mitigation strategies" rounds=5

# Structured expert debate format
/project:multi-mind-debate "Scaling transformer architectures beyond GPU limits"
```

#### Conversation History Search
```bash
# Search across all your Claude conversations
/project:search-prompts "machine learning pipeline"
/project:search-prompts "debugging memory issues"
/project:search-prompts "database optimization"
```

#### Deep Code Analysis
```bash
# Analyze any function with detailed insights
/project:analyze-function train.py:detect_words_gpu
/project:analyze-function utils.js validateInput
```

## Key Features

- **Dynamic Specialist Assignment**: AI automatically selects 4-6 experts based on topic complexity
- **Error Decorrelation**: Different specialists catch different types of blind spots
- **Web Search Integration**: Fresh knowledge acquisition each round
- **Anti-Repetition Mechanisms**: Progressive insight building without circular discussions
- **Configurable Workflows**: Adjust rounds and depth based on needs

## Contributing

Feel free to:
- Add new custom commands
- Improve existing guides
- Share your own Claude Code workflows
- Submit pull requests with enhancements

## License

Open source - modify and adapt for your specific needs.
