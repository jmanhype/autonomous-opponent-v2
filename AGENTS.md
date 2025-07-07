# AGENTS.md - Coding Agent Guidelines

## Essential Commands

**Build/Test/Lint:**
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run single test file
- `mix test --cover` - Run tests with coverage (40% threshold)
- `mix format` - Format code (required before commits)
- `mix credo --strict` - Lint code quality
- `mix dialyzer` - Type checking (if configured)
- `mix compile --warnings-as-errors` - Strict compilation

**Development:**
- `iex -S mix phx.server` - Start server with REPL
- `mix ecto.reset` - Reset database
- `mix deps.get` - Install dependencies

## Code Style Guidelines

**Elixir Conventions:**
- Use `snake_case` for variables, functions, modules use `PascalCase`
- Prefer pattern matching over conditionals
- Use `with` for complex nested operations
- Always add `@moduledoc` and `@doc` for public functions
- Import order: stdlib, deps, local modules
- Use `alias` for module shortcuts, avoid `import` unless necessary

**Error Handling:**
- Return `{:ok, result}` or `{:error, reason}` tuples
- Use `case` statements for pattern matching results
- Implement proper supervision trees for GenServers

**Testing:**
- Test files end with `_test.exs`
- Use descriptive test names: `test "should return error when invalid input"`
- Aim for >40% coverage, focus on critical paths

## Pre-Commit Requirements (from .github/claude-instructions.md)
1. `mix format` (mandatory)
2. `mix test` (must pass)
3. `mix credo --strict` (must pass)
4. `mix compile --warnings-as-errors` (must pass)