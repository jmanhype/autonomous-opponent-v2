# Claude Code Custom Commands Collection

This directory contains reusable custom commands for Claude Code that enhance productivity and enable advanced workflows.

## Installation

### Option 1: Project-Level Commands
Copy commands to your project's `.claude/commands/` directory:
```bash
# In your project root
mkdir -p .claude/commands
cp claude-commands/*.md .claude/commands/
```

### Option 2: Global Commands  
Copy commands to your global Claude directory for use across all projects:
```bash
# Global installation
mkdir -p ~/.claude/commands
cp claude-commands/*.md ~/.claude/commands/
```

## Available Commands

### 🔍 Search Commands

#### `/project:search-prompts` or `/user:search-prompts`
**Purpose**: Search across all your Claude Code conversation history  
**Usage**: `/project:search-prompts "search term"`

**What it provides**:
- Multi-source search across database and project histories
- Session-based search with resumable conversation IDs
- Advanced pattern matching and temporal filtering
- Conversation summary search for high-level topics
- Integration with `claude --resume` for continuing relevant discussions

**Example**: `/project:search-prompts "machine learning pipeline"`

### 📝 Code Analysis Commands

#### `/project:analyze-function` or `/user:analyze-function`
**Purpose**: Deep line-by-line analysis of any function in your codebase  
**Usage**: `/project:analyze-function filename:function_name` or `/project:analyze-function filename function_name`

**What it provides**:
- Technical implementation details and performance implications
- Edge cases and potential issues  
- Connection to broader codebase architecture
- Critical details often missed from casual reading
- Mathematical foundations and optimization techniques

**Example**: `/project:analyze-function train.py:detect_words_gpu`

### 🧠 Multi-Mind Collaboration Command

#### `/project:multi-mind` or `/user:multi-mind`
**Purpose**: Execute multi-specialist collaborative analysis using independent subagents  
**Usage**: `/project:multi-mind "topic" [rounds=3]`

**Features**:
- **Subagent Architecture**: Each specialist runs as independent subagent via Task tool
- **Parallel Processing**: True concurrent execution of specialist research
- **Dynamic Assignment**: 4-6 specialists chosen based on topic complexity
- **Web Search Integration**: Each subagent has WebSearch access for fresh knowledge
- **Anti-Repetition**: Progressive insight building across rounds
- **Cross-Pollination**: Specialists review and build on each other's findings

**Examples**:
```bash
/project:multi-mind "Should we implement quantum error correction in our ML pipeline?"
/project:multi-mind "Climate change mitigation strategies" rounds=5
/project:multi-mind "Scaling transformer architectures beyond current GPU memory limits"
```

### 📄 Session Management Commands

#### `/project:page` or `/user:page`
**Purpose**: Save complete session history with citations, then prepare for memory compaction  
**Usage**: `/project:page [filename_prefix] [output_directory]`

**Features**:
- **OS-Style Paging**: Saves conversation state to disk before memory compaction
- **Full Citations**: Complete source attribution and indexed references
- **Compact Summary**: Executive summary included at top of full history
- **Memory Management**: Prepares for `/compact` to free Claude's context
- **Default Location**: Saves to current working directory unless specified

**Generated Files**:
- `{prefix}-{timestamp}-full.md` - Complete history with citations
- `{prefix}-{timestamp}-compact.md` - Executive summary for future loading

**Example**: 
```bash
/project:page                                    # Basic usage
/project:page feature-implementation             # Custom prefix
/project:page bug-fix ./docs/sessions/          # Custom location
# After completion, run: /compact
```

### 🔧 Command Management

#### `/project:crud-claude-commands` or `/user:crud-claude-commands`
**Purpose**: Dynamically manage Claude Code custom commands (Create, Read, Update, Delete)  
**Usage**: `/project:crud-claude-commands <operation> <command-name> [content]`

**Operations**:
- **CREATE**: Generate new command from description
- **READ**: Display existing command content
- **UPDATE**: Modify command based on instructions
- **DELETE**: Remove command from system
- **LIST**: Show all available commands

**Features**:
- **Dynamic Generation**: Creates commands from natural language descriptions
- **Auto-Sync**: Automatically updates agent-guides repository if present
- **Git Integration**: Commits and pushes changes to remote
- **Template Compliance**: Ensures proper command structure
- **Error Handling**: Fuzzy matching for command names

**Examples**:
```bash
/project:crud-claude-commands create git-flow "Create git workflow automation"
/project:crud-claude-commands update page "Add JSON export format"
/project:crud-claude-commands delete old-command
/project:crud-claude-commands list
```

## Multi-Mind System Architecture

### Core Principles
- **Many Minds**: 4-6 dynamically assigned specialists per topic
- **Unique Specialists**: Each has distinct domain expertise with minimal correlation
- **Error Decorrelation**: Different analytical approaches catch different blind spots  
- **Active Moderation**: Drives progress, prevents repetition, synthesizes insights
- **Progressive Knowledge**: Web search integration ensures fresh information each round

### Specialist Selection Criteria
- Unique domain expertise relevant to the topic
- Different methodological approaches (quantitative/qualitative, theoretical/practical)
- Varied temporal perspectives (historical, current, future-focused)
- Distinct risk/opportunity sensitivities
- Independent information sources and knowledge bases

### Anti-Repetition Mechanisms
- Moderator tracks coverage vs. gaps requiring exploration
- Specialists build on previous insights rather than restating
- Focus on unique expertise contributions to collective understanding
- Challenge emerging consensus from specialist perspectives

## Command Development

### Creating New Commands
1. Create a new `.md` file in this directory
2. Use `$ARGUMENTS` placeholder for dynamic parameters
3. Include clear usage instructions and examples
4. Test the command in a Claude Code session
5. Update this README with the new command

### Command Template
```markdown
# Command Description
Brief description of what this command does.

**Usage**: `/project:command-name $ARGUMENTS`

## Instructions
Detailed instructions for Claude on how to execute this command.

## Examples
Example usage scenarios and expected outputs.
```

### Best Practices
- Make commands reusable across different projects
- Include clear success criteria and expected outcomes
- Provide examples that demonstrate the command's value
- Use namespacing with subdirectories for related commands
- Document any prerequisites or dependencies

## Contributing

To contribute new commands:
1. Create the command file following the template
2. Test it in a real Claude Code session  
3. Add documentation to this README
4. Submit a pull request with clear description of the command's purpose and benefits

## Command Categories

### 🔍 Search & Discovery
- `search-prompts.md` - Comprehensive conversation history search

### 📊 Analysis & Research
- `analyze-function.md` - Deep function analysis
- `multi-mind.md` - Multi-specialist collaborative analysis with subagents

### 📄 Session Management
- `page.md` - Session history dump with citations and memory management

### 🔧 Development Workflow
- `crud-claude-commands.md` - Dynamic command management (CRUD operations)

### 📚 Documentation & Learning  
*(Future commands for documentation generation)*

### 🚀 Deployment & Operations
*(Future commands for deployment assistance)*

## License

These commands are provided under the same license as the agent-guides repository. Feel free to modify and adapt them for your specific needs.

## Related Resources

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/slash-commands)
- [Claude Custom Commands Guide](../claude-custom-commands.md)
- [Claude Code Search Best Practices](../claude-code-search-best-practices.md)
