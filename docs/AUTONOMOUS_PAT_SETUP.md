# Setting up Personal Access Token for Autonomous Workflows

GitHub Actions using `GITHUB_TOKEN` cannot trigger other workflows. This is a security feature to prevent infinite loops. To allow the autonomous task runner to create PRs that trigger Claude, you need a Personal Access Token (PAT).

## Steps to Create PAT:

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a descriptive name: `Autonomous Task Runner PAT`
4. Set expiration (recommend 90 days and rotate regularly)
5. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
6. Generate token and copy it immediately

## Add to Repository:

1. Go to your repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `AUTONOMOUS_PAT`
4. Value: Paste your PAT
5. Click "Add secret"

## How it Works:

- When autonomous runner uses PAT instead of GITHUB_TOKEN:
  - ✅ Can create PRs that trigger Claude workflows
  - ✅ Can create comments that trigger @claude mentions
  - ✅ Appears as coming from your account (not github-actions bot)

## Security Notes:

- PATs are powerful - keep them secure
- Rotate regularly (every 90 days)
- Use fine-grained PATs if available for your organization
- Never commit PATs to code

## Alternative Solutions:

1. **GitHub App**: More secure but complex setup
2. **Webhook**: External service to trigger workflows
3. **Manual Trigger**: Keep current setup, manually nudge Claude

The PAT approach is the simplest solution for autonomous workflows that need to trigger other workflows.