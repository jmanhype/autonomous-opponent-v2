# Disabled Claude Workflows

These workflows were disabled to avoid duplicate Claude executions and reduce API costs.

## Disabled Workflows:
- `claude_code.yml` - Redundant with main PR assistant
- `claude-pr-assistant-enhanced.yml` - Replaced by main PR assistant
- `claude-code-validator.yml` - Validation integrated into main workflow
- `claude_code_login.yml` - One-time setup, no longer needed
- `claude-oauth-login.yml` - One-time setup, no longer needed

## Active Claude Workflows:
- `claude-pr-assistant.yml` - Main Claude assistant (responds to @claude)
- `claude-doc-enhancer.yml` - Documentation enhancement on PR changes
- `claude-oauth-setup.yml` - OAuth token management
- `claude-performance-advisor.yml` - Performance analysis
- `claude-vsm-advisor.yml` - VSM-specific advice

## CI/CD Workflows with Claude Context:
- `vsm-enhanced-ci-cd.yml` - VSM CI/CD pipeline (doesn't execute Claude)
- `vsm-unified-pipeline.yml` - Unified pipeline with monitoring

To re-enable any workflow, move it back from this directory and remove the `.disabled` extension.