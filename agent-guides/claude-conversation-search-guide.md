# Claude Code Conversation Search Guide

A comprehensive guide to searching through your Claude Code conversation history, prompts, and insights across all your projects and sessions.

## Overview

Claude Code stores your conversation history in multiple locations, each offering different search capabilities and granularities. This guide covers all available methods to find relevant discussions, prompts, and insights from your past interactions.

## Storage Locations

### 1. SQLite Database (`~/.claude/__store.db`)
**Contains**: Complete conversation history with structured metadata
- User messages and assistant responses
- Session information and timestamps  
- Conversation summaries
- Message relationships and threading

### 2. JSON Configuration (`~/.claude.json`)
**Contains**: Project-specific conversation history
- Command history for each project directory
- Recent prompts and interactions
- Project-level conversation metadata

### 3. Session Management
**Contains**: Active and resumable session states
- Session IDs for continuing conversations
- Working directory context
- Conversation state and memory

## Search Methods

### Database Search (Most Comprehensive)

#### Basic Keyword Search
```bash
sqlite3 ~/.claude/__store.db "
SELECT 
    b.session_id,
    datetime(b.timestamp, 'unixepoch') as date,
    substr(u.message, 1, 100) as preview
FROM user_messages u 
JOIN base_messages b ON u.uuid = b.uuid 
WHERE u.message LIKE '%keyword%' 
ORDER BY b.timestamp DESC 
LIMIT 10;"
```

#### Advanced Pattern Search
```bash
# Search with multiple keywords
sqlite3 ~/.claude/__store.db "
SELECT DISTINCT b.session_id, datetime(b.timestamp, 'unixepoch') as date
FROM user_messages u 
JOIN base_messages b ON u.uuid = b.uuid 
WHERE (u.message LIKE '%keyword1%' OR u.message LIKE '%keyword2%')
AND u.message LIKE '%required_term%'
ORDER BY b.timestamp DESC;"
```

#### Session Context Search
```bash
# Find sessions by working directory
sqlite3 ~/.claude/__store.db "
SELECT DISTINCT 
    b.session_id,
    b.cwd,
    datetime(MIN(b.timestamp), 'unixepoch') as start_time,
    COUNT(*) as message_count
FROM base_messages b
WHERE b.cwd LIKE '%project_name%'
GROUP BY b.session_id
ORDER BY MIN(b.timestamp) DESC;"
```

### Project History Search

#### Python Script for JSON Search
```python
import json
import re
from datetime import datetime

def search_conversations(search_term, max_results=20):
    """Search through all project conversation histories"""
    try:
        with open('/Users/YOUR_USERNAME/.claude.json', 'r') as f:
            data = json.load(f)
        
        results = []
        if 'projects' in data:
            for project_path, project_data in data['projects'].items():
                if 'history' in project_data and project_data['history']:
                    for i, item in enumerate(project_data['history']):
                        text = ""
                        if isinstance(item, dict) and 'display' in item:
                            text = item['display']
                        elif isinstance(item, str):
                            text = item
                        
                        if text and search_term.lower() in text.lower():
                            results.append({
                                'project': project_path.split('/')[-1],
                                'full_path': project_path,
                                'index': i,
                                'text': text,
                                'relevance_score': text.lower().count(search_term.lower()),
                                'length': len(text)
                            })
        
        # Sort by relevance and recency
        results.sort(key=lambda x: (x['relevance_score'], x['length']), reverse=True)
        return results[:max_results]
    
    except Exception as e:
        print(f"Error searching conversations: {e}")
        return []

# Usage example
results = search_conversations("machine learning")
for result in results:
    print(f"Project: {result['project']}")
    print(f"Relevance: {result['relevance_score']} matches")
    print(f"Text: {result['text'][:150]}...")
    print("---")
```

#### Command Line JSON Search
```bash
# Search for specific terms in project histories
python3 -c "
import json
data = json.load(open('/Users/$USER/.claude.json'))
search_term = 'your_search_term'
for project, project_data in data.get('projects', {}).items():
    for i, item in enumerate(project_data.get('history', [])):
        text = item.get('display', str(item)) if isinstance(item, dict) else str(item)
        if search_term.lower() in text.lower():
            print(f'Project: {project.split(\"/\")[-1]}')
            print(f'Text: {text[:100]}...')
            print('---')
"
```

### Session Management Search

#### Find Resumable Sessions
```bash
# List recent sessions with context
sqlite3 ~/.claude/__store.db "
SELECT 
    b.session_id,
    b.cwd,
    datetime(MIN(b.timestamp), 'unixepoch') as start_date,
    datetime(MAX(b.timestamp), 'unixepoch') as last_activity,
    COUNT(*) as total_messages
FROM base_messages b
GROUP BY b.session_id, b.cwd
ORDER BY MAX(b.timestamp) DESC 
LIMIT 15;"
```

#### Resume Specific Conversations
```bash
# Resume a session by ID
claude --resume SESSION_ID

# Interactive session selection
claude --resume

# Continue most recent conversation
claude --continue
```

### Advanced Search Techniques

#### Time-Based Filtering
```bash
# Conversations from last week
sqlite3 ~/.claude/__store.db "
SELECT b.session_id, datetime(b.timestamp, 'unixepoch') as date, 
       substr(u.message, 1, 100) as preview
FROM user_messages u 
JOIN base_messages b ON u.uuid = b.uuid 
WHERE u.message LIKE '%search_term%' 
AND b.timestamp > strftime('%s', 'now', '-7 days')
ORDER BY b.timestamp DESC;"

# Conversations from specific date range
sqlite3 ~/.claude/__store.db "
SELECT b.session_id, datetime(b.timestamp, 'unixepoch') as date
FROM user_messages u 
JOIN base_messages b ON u.uuid = b.uuid 
WHERE u.message LIKE '%search_term%' 
AND date(b.timestamp, 'unixepoch') BETWEEN '2024-01-01' AND '2024-01-31';"
```

#### Content-Length Filtering
```bash
# Find longer, more detailed conversations
sqlite3 ~/.claude/__store.db "
SELECT b.session_id, datetime(b.timestamp, 'unixepoch') as date,
       length(u.message) as msg_length,
       substr(u.message, 1, 150) as preview
FROM user_messages u 
JOIN base_messages b ON u.uuid = b.uuid 
WHERE u.message LIKE '%search_term%' 
AND length(u.message) > 200
ORDER BY length(u.message) DESC;"
```

#### Multi-Keyword Boolean Search
```bash
# AND logic (all terms must be present)
sqlite3 ~/.claude/__store.db "
SELECT DISTINCT b.session_id, substr(u.message, 1, 100) as preview
FROM user_messages u 
JOIN base_messages b ON u.uuid = b.uuid 
WHERE u.message LIKE '%term1%' 
AND u.message LIKE '%term2%' 
AND u.message LIKE '%term3%';"

# OR logic (any term can be present)
sqlite3 ~/.claude/__store.db "
SELECT DISTINCT b.session_id, substr(u.message, 1, 100) as preview
FROM user_messages u 
JOIN base_messages b ON u.uuid = b.uuid 
WHERE u.message LIKE '%term1%' 
OR u.message LIKE '%term2%' 
OR u.message LIKE '%term3%';"
```

## Search Strategies

### 1. Hierarchical Search Approach
```
1. Start with broad topic keywords
2. Narrow down with specific technical terms
3. Filter by time period if relevant
4. Focus on project-specific results
5. Resume most relevant sessions
```

### 2. Multi-Source Strategy
```
1. Search database for comprehensive results
2. Check project histories for recent context
3. Look for resumable sessions
4. Cross-reference findings across sources
```

### 3. Context-Driven Search
```
1. Search by project directory/codebase
2. Filter by conversation length (detailed vs. quick)
3. Time-bound searches (recent vs. historical)
4. Technical domain filtering
```

## Custom Search Commands

### Create a Search Alias
```bash
# Add to your ~/.bashrc or ~/.zshrc
alias claude-search='python3 -c "
import sys, json
search_term = sys.argv[1] if len(sys.argv) > 1 else input(\"Search term: \")
data = json.load(open(\"/Users/$USER/.claude.json\"))
matches = []
for project, project_data in data.get(\"projects\", {}).items():
    for item in project_data.get(\"history\", []):
        text = item.get(\"display\", str(item)) if isinstance(item, dict) else str(item)
        if search_term.lower() in text.lower():
            matches.append((project.split(\"/\")[-1], text[:100]))
print(f\"Found {len(matches)} matches:\")
for project, text in matches[:10]:
    print(f\"{project}: {text}...\")
"'

# Usage
claude-search "machine learning"
```

### Database Search Function
```bash
# Add to your shell profile
claude-db-search() {
    local search_term="$1"
    if [ -z "$search_term" ]; then
        echo "Usage: claude-db-search <search_term>"
        return 1
    fi
    
    sqlite3 ~/.claude/__store.db "
    SELECT 
        b.session_id,
        datetime(b.timestamp, 'unixepoch') as date,
        substr(u.message, 1, 150) as preview
    FROM user_messages u 
    JOIN base_messages b ON u.uuid = b.uuid 
    WHERE u.message LIKE '%$search_term%' 
    ORDER BY b.timestamp DESC 
    LIMIT 15;"
}
```

## Search Optimization Tips

### 1. Keyword Selection
- Use **domain-specific terminology** from your field
- Include **project names** and **file names** mentioned in conversations
- Try **synonyms** and **variations** of key concepts
- Search for **error messages** or **specific issues** you discussed

### 2. Time Management
- Use **time filters** to focus on recent vs. historical discussions
- Search by **project creation dates** for development timelines
- Filter **seasonal work** or **sprint periods**

### 3. Context Preservation
- Note **session IDs** of valuable conversations
- **Bookmark** frequently referenced discussions
- Create **project-specific search aliases**
- Maintain **topic indexes** for complex projects

### 4. Search Refinement
- Start **broad**, then **narrow down**
- Use **multiple search terms** combined with AND/OR logic
- **Cross-reference** results across different search methods
- **Verify relevance** by resuming sessions and checking context

## Integration with Workflows

### 1. Research Preparation
Before starting new projects, search for:
- Previous similar work or discussions
- Lessons learned from past projects  
- Technical approaches that worked/failed
- Relevant conversation threads to resume

### 2. Problem-Solving
When encountering issues:
- Search for similar error messages or problems
- Find previous debugging sessions
- Locate relevant technical discussions
- Resume sessions where solutions were found

### 3. Knowledge Management
- Regular searches to identify valuable insights
- Create summaries of important conversation threads
- Extract and document key findings
- Build personal knowledge bases from conversation history

## Troubleshooting

### Common Issues
1. **Empty results**: Check spelling, try synonyms, broaden search terms
2. **Too many results**: Add more specific terms, use time filters
3. **Database access errors**: Check file permissions, ensure Claude Code is not running
4. **JSON parsing errors**: Verify file integrity, check for corruption

### Performance Tips
- **Index frequently searched terms** in your own notes
- **Use shorter search terms** for broader results
- **Combine multiple search methods** for comprehensive coverage
- **Cache important session IDs** for quick access

## See Also

- [Claude Code Search Best Practices](claude-code-search-best-practices.md)
- [Custom Commands Collection](claude-commands/)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/overview)
