# Claude Code Search Best Practices

A comprehensive guide to effectively searching docs and code using Claude Code's powerful natural language capabilities.

## Overview

Claude Code goes beyond traditional text search by understanding code structure, relationships, and patterns. This guide covers the most effective techniques for finding information in your codebase.

## 1. Natural Language Search Capabilities

Claude Code automatically searches and indexes your codebase. Use natural language to find what you need:

### Basic Searches
```
> find the files that handle user authentication
> how is logging implemented in this project?
> show me all the API endpoints for user management
> where is the database configuration?
> locate error handling middleware
```

### Specific Analysis
```
> trace the login process from front-end to database
> explain how these authentication files work together
> find deprecated API usage in our codebase
> show me payment processing logic
```

## 2. Optimize with CLAUDE.md Files

Create `CLAUDE.md` files to provide search context and improve results:

```markdown
# Core Files
- auth.py: User authentication and authorization
- models/user.py: User data models
- api/endpoints.py: REST API definitions
- utils/logger.py: Centralized logging functionality

# Common Commands
- npm test: Run test suite
- npm run build: Build the project
- docker-compose up: Start local environment

# Architecture Notes
- Uses microservices pattern
- PostgreSQL database with Redis caching
- Event-driven architecture with message queues
- JWT-based authentication

# Search Aliases
- "auth" refers to authentication system
- "api" refers to REST endpoints in /api directory
- "models" refers to data models in /models directory
```

## 3. Effective Search Strategies

### Start Broad, Then Narrow
```
1. > give me an overview of this codebase
2. > explain the main architecture patterns used here
3. > how is user authentication handled specifically?
4. > show me the JWT token validation code
```

### Use Domain-Specific Language
```
> find all React components that use hooks
> show me GraphQL resolvers for user queries
> locate middleware functions
> find all database migrations
> show me test files for the authentication module
```

### Search by Functionality
```
> find code that handles file uploads
> show me email sending functionality
> locate caching implementation
> find validation logic for user input
> show me error reporting mechanisms
```

## 4. Advanced Search Techniques

### Cross-Reference Analysis
```
> how do the authentication files work together?
> trace the data flow from API to database
> show me dependencies between these modules
> explain the relationship between User and Profile models
```

### Pattern Recognition
```
> find all files using the observer pattern
> show me components that follow the same structure as UserCard.js
> locate similar error handling patterns
> find all classes that implement the Repository pattern
```

### Code Evolution and Maintenance
```
> find deprecated API usage
> show me TODO comments across the codebase
> locate files that need refactoring
> find unused imports or functions
> show me files with high complexity
```

## 5. Documentation and External Search

### Web-Based Research
```
> search for best practices for React testing
> find documentation for this specific API
> look up the latest version of this library
> find examples of implementing OAuth with this framework
```

### Internal Documentation
```
> read the README and explain the setup process
> summarize the API documentation
> explain the deployment guide
> show me the changelog for recent updates
```

## 6. Custom Search Commands

Create reusable search commands in `.claude/commands/` for frequent tasks:

### API Endpoint Finder
**`.claude/commands/find-api.md`:**
```markdown
Find all API endpoints related to: $ARGUMENTS

1. Search for route definitions containing the keyword
2. Find corresponding controllers and handlers
3. Locate validation middleware and schemas
4. Show authentication/authorization requirements
5. List any tests for these endpoints
6. Display example requests/responses if available
```

**Usage:** `/project:find-api user management`

### Security Audit Command
**`.claude/commands/security-audit.md`:**
```markdown
Perform a security audit focusing on: $ARGUMENTS

1. Find authentication and authorization code
2. Locate input validation and sanitization
3. Check for SQL injection vulnerabilities
4. Review error handling for information leakage
5. Examine session management
6. Look for hardcoded credentials or secrets
```

**Usage:** `/project:security-audit authentication`

### Code Quality Review
**`.claude/commands/code-quality.md`:**
```markdown
Review code quality for: $ARGUMENTS

1. Find the specified files or modules
2. Check for code duplication
3. Analyze complexity and readability
4. Review naming conventions
5. Check for proper error handling
6. Suggest refactoring opportunities
```

**Usage:** `/project:code-quality user service`

## 7. Search Performance Tips

### Be Specific
❌ **Vague:** "Find React stuff"
✅ **Specific:** "Find React components that use useState hook"

❌ **Broad:** "Show me the database code"
✅ **Targeted:** "Show me the User model and its database queries"

### Use Context
```
> find all API routes in the /api/v1/users directory
> show me React components in the dashboard module
> locate TypeScript interfaces for payment processing
> find Python classes that inherit from BaseModel
```

### Iterate Your Search
```
1. > show me the authentication system overview
2. > focus on the JWT token handling specifically
3. > explain how token refresh works
4. > show me the middleware that validates tokens
```

### Combine Multiple Approaches
```
> find the user authentication files, then explain how they connect to the database models, and show me any related tests
```

## 8. Search Best Practices Checklist

### Before You Start
- [ ] Create or update `CLAUDE.md` with project context
- [ ] Understand the project's directory structure
- [ ] Know the main technologies and frameworks used

### During Search
- [ ] Start with broad overview questions
- [ ] Use project-specific terminology
- [ ] Ask for relationships between components
- [ ] Request concrete examples
- [ ] Verify your understanding

### Search Questions to Ask
- [ ] "How does X connect to Y?"
- [ ] "What are the dependencies of this module?"
- [ ] "Show me examples of how this is used"
- [ ] "Are there any similar patterns elsewhere?"
- [ ] "What tests exist for this functionality?"

## 9. Troubleshooting Search Issues

### When Search Results Are Poor
1. **Update CLAUDE.md** with better context
2. **Be more specific** in your queries
3. **Use exact function/class names** if known
4. **Ask for file listings** first, then drill down

### When You Can't Find Something
```
> list all files in the project with brief descriptions
> show me the directory structure
> what are the main entry points for this application?
> find any references to [specific term] in comments or documentation
```

### When Results Are Too Broad
```
> focus only on the frontend components
> limit search to the authentication module
> show me just the database-related files
> find only the test files for this feature
```

## 10. Advanced Search Patterns

### Architecture Understanding
```
> explain the overall system architecture
> show me how data flows through the application
> what are the main architectural patterns used?
> how are concerns separated in this codebase?
```

### Integration Points
```
> find all external API integrations
> show me database connection and configuration
> locate third-party service integrations
> find environment-specific configurations
```

### Performance Investigation
```
> find potential performance bottlenecks
> show me caching implementations
> locate database query optimizations
> find async/await usage patterns
```

## Conclusion

Effective searching in Claude Code combines natural language queries with understanding of your project's structure and terminology. The key is to:

1. **Provide context** through CLAUDE.md files
2. **Start broad and narrow down** your search
3. **Use domain-specific language**
4. **Ask for relationships and connections**
5. **Create custom commands** for frequent searches
6. **Iterate and refine** your queries

Remember: Claude Code doesn't just search text—it understands code structure, patterns, and relationships, making it significantly more powerful than traditional search tools.

## See Also

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Custom Commands Guide](claude-custom-commands.md)
- [Common Workflows](https://docs.anthropic.com/en/docs/claude-code/common-workflows)
- [Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
