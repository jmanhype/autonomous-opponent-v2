# Instructions for Claude Autonomous Mode

When working on autonomous tasks, ALWAYS follow these steps before pushing:

## Pre-Commit Checklist

1. **Format Code**
   ```bash
   mix format
   ```

2. **Run Tests**
   ```bash
   mix test
   ```

3. **Check Code Quality**
   ```bash
   mix credo --strict
   ```

4. **Type Check** (if dialyzer is set up)
   ```bash
   mix dialyzer
   ```

5. **Verify Compilation**
   ```bash
   mix compile --warnings-as-errors
   ```

6. **Test Docker Build** (for major changes)
   ```bash
   docker build -t test-build .
   ```

## Common Issues and Fixes

### Formatting Issues
- Always run `mix format` before committing
- Check `.formatter.exs` for project formatting rules

### Test Failures
- New code must have tests
- Aim for >40% coverage (current threshold)
- Use `mix test --cover` to check coverage

### Credo Issues
- Follow Elixir style guide
- Fix refactoring opportunities
- Remove TODO comments after implementing

### Docker Build Failures
- Usually caused by syntax errors
- Check for missing dependencies in mix.exs
- Ensure all files are properly closed

## CI/CD Pipeline

The following checks run on every PR:
1. Code formatting
2. Credo analysis  
3. Compilation
4. Tests with coverage
5. Security scanning
6. Docker build

## Validation Helper

Before pushing, you can comment `@claude-validate` on your PR to run validation locally.

## Task Completion

When a task is complete and all CI/CD checks pass:
1. Update the PR description with implementation summary
2. Confirm all acceptance criteria are met
3. The PR will be auto-merged if all checks pass
4. Task status will be automatically updated to "done"

## Adding New Tasks

After completing current tasks:
1. Run the task generation workflow
2. Analyze codebase for logical next steps
3. Add tasks that build on completed work
4. Ensure proper dependencies are set
5. Focus on advancing VSM implementation

Remember: The goal is to produce production-ready code that passes all quality gates!