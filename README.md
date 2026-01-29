# Claude Deploy Hook

A universal deployment hook for [Claude Code](https://claude.ai/claude-code) with smart environment variable management. Supports multiple cloud providers with a modular architecture.

## Features

- **Smart env var sync** - Automatically adds new vars, updates changed vars, prompts before removing
- **Secret preservation** - Always preserves secrets from live deployments
- **Multi-provider** - GCP, Firebase, Vercel, Cloudflare, Railway (easily extensible)
- **Auto-detection** - Detects provider from project files
- **Dry run mode** - Preview changes before deploying
- **Non-destructive defaults** - Keeps existing vars in non-interactive mode

## Supported Providers

| Provider | ID | Auto-detects from |
|----------|-----|-------------------|
| GCP Cloud Run | `gcp-cloud-run` | `Dockerfile`, `service.yaml` |
| GCP Cloud Functions | `gcp-cloud-functions` | `cloudfunctions.yaml`, `.gcloudignore` |
| Firebase Functions | `gcp-firebase-functions` | `firebase.json`, `functions/` |
| Vercel | `vercel` | `vercel.json`, `.vercel/` |
| Cloudflare Workers | `cloudflare-workers` | `wrangler.toml` |
| Cloudflare Pages | `cloudflare-pages` | `wrangler.toml` with `pages_build_output_dir` |
| Railway | `railway` | `railway.json`, `railway.toml` |
| Kubernetes | `kubernetes` | `k8s/`, `deployment.yaml`, `kustomization.yaml`, `Chart.yaml` |
| AWS Lambda | `aws-lambda` | `serverless.yml`, `template.yaml` (SAM) |
| AWS ECS/Fargate | `aws-ecs` | `ecs-task-def.json`, `task-definition.json` |
| Azure Functions | `azure-functions` | `host.json`, `local.settings.json` |
| Heroku | `heroku` | `Procfile`, `app.json`, `heroku.yml` |
| Fly.io | `flyio` | `fly.toml` |
| Render | `render` | `render.yaml` |
| Netlify | `netlify` | `netlify.toml`, `.netlify/` |

## Installation

### Quick Install

```bash
# Clone into your project's .claude/hooks directory
git clone https://github.com/sterlingsky/claude-deploy-hook.git .claude/hooks
```

### Manual Install

1. Copy the files to `.claude/hooks/` in your project:
   ```
   .claude/hooks/
   ├── deploy.sh
   ├── lib/
   │   └── env-compare.sh
   └── providers/
       ├── gcp-cloud-run.sh
       ├── gcp-cloud-functions.sh
       ├── gcp-firebase-functions.sh
       ├── vercel.sh
       ├── cloudflare-workers.sh
       ├── cloudflare-pages.sh
       ├── railway.sh
       ├── kubernetes.sh
       ├── aws-lambda.sh
       ├── aws-ecs.sh
       ├── azure-functions.sh
       ├── heroku.sh
       ├── flyio.sh
       ├── render.sh
       └── netlify.sh
   ```

2. Make scripts executable:
   ```bash
   chmod +x .claude/hooks/deploy.sh .claude/hooks/lib/*.sh .claude/hooks/providers/*.sh
   ```

3. Add to `.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "command": "if echo \"$TOOL_INPUT\" | grep -qE '(gcloud run deploy|gcloud functions deploy|firebase deploy|vercel|wrangler deploy|railway up|kubectl apply|helm upgrade|sam deploy|serverless deploy|aws lambda|aws ecs|func azure|heroku|fly deploy|netlify deploy)'; then \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/deploy.sh; fi",
               "timeout": 600
             }
           ]
         }
       ]
     }
   }
   ```

## Usage

### Command Line

```bash
# Auto-detect provider and deploy
.claude/hooks/deploy.sh

# Specify provider explicitly
.claude/hooks/deploy.sh --provider=gcp-cloud-run

# Dry run (show what would happen without deploying)
.claude/hooks/deploy.sh --dry-run

# Use specific env file
.claude/hooks/deploy.sh --env-file=.env.staging

# List available providers
.claude/hooks/deploy.sh --list-providers

# Show help
.claude/hooks/deploy.sh --help
```

### As Claude Code Hook

The hook automatically triggers when you run deployment commands like:
- `gcloud run deploy`
- `gcloud functions deploy`
- `firebase deploy`
- `vercel`
- `wrangler deploy`
- `railway up`
- `kubectl apply`
- `helm upgrade`
- `sam deploy`
- `serverless deploy`
- `aws lambda update-function-code`
- `aws ecs update-service`
- `func azure functionapp publish`
- `heroku` (git push)
- `fly deploy`
- `netlify deploy`

### As Slash Command

Create `.claude/commands/deploy.md`:
```markdown
# Deploy

Deploy to cloud with smart env var management.

\`\`\`bash
"$CLAUDE_PROJECT_DIR"/.claude/hooks/deploy.sh
\`\`\`
```

Then use `/deploy` in Claude Code.

## How It Works

1. **Detects provider** from project files (or uses `--provider` flag)
2. **Fetches live env vars** from the deployed service
3. **Reads local env file** (`.env.production`, `.env`, etc.)
4. **Compares** live vs local:
   - New vars in local → **Auto-add**
   - Changed vars → **Auto-update**
   - Vars in live but not local → **Prompt to remove** (keeps by default)
5. **Preserves secrets** from the live deployment
6. **Deploys** with the merged configuration

## Configuration

### Environment Variables

#### Common
| Variable | Description |
|----------|-------------|
| `DEPLOY_PROVIDER` | Override auto-detection |
| `DEPLOY_ENV_FILE` | Path to local env file |
| `DEPLOY_DRY_RUN=1` | Enable dry run mode |

#### GCP Cloud Run
| Variable | Description | Default |
|----------|-------------|---------|
| `GOOGLE_CLOUD_PROJECT` | GCP project ID | (required) |
| `CLOUD_RUN_SERVICE` | Service name | (required) |
| `CLOUD_RUN_REGION` | Region | `us-central1` |

#### GCP Cloud Functions
| Variable | Description | Default |
|----------|-------------|---------|
| `GOOGLE_CLOUD_PROJECT` | GCP project ID | (required) |
| `CLOUD_FUNCTION_NAME` | Function name | (required) |
| `CLOUD_FUNCTIONS_REGION` | Region | `us-central1` |
| `GCP_FUNCTION_GEN` | Generation (1 or 2) | `2` |
| `GCP_FUNCTION_RUNTIME` | Runtime | `nodejs20` |
| `GCP_FUNCTION_TRIGGER` | Trigger type | `http` |

#### Firebase Functions
| Variable | Description | Default |
|----------|-------------|---------|
| `GOOGLE_CLOUD_PROJECT` | GCP project ID | (required) |
| `FIREBASE_FUNCTIONS_GEN` | Generation (1 or 2) | `2` |

#### Vercel
| Variable | Description | Default |
|----------|-------------|---------|
| `VERCEL_PROJECT` | Project name | (auto-detect) |
| `VERCEL_ENV` | Environment | `production` |

#### Cloudflare Workers
| Variable | Description | Default |
|----------|-------------|---------|
| `CF_WORKER_NAME` | Worker name | (from wrangler.toml) |
| `CF_ACCOUNT_ID` | Account ID | (optional, for API) |
| `CF_API_TOKEN` | API token | (optional, for API) |

#### Cloudflare Pages
| Variable | Description | Default |
|----------|-------------|---------|
| `CF_PAGES_PROJECT` | Project name | (required) |
| `CF_PAGES_BRANCH` | Branch | `main` |
| `CF_ACCOUNT_ID` | Account ID | (required for env vars) |
| `CF_API_TOKEN` | API token | (required for env vars) |

#### Railway
| Variable | Description | Default |
|----------|-------------|---------|
| `RAILWAY_ENVIRONMENT` | Environment | `production` |

#### Kubernetes
| Variable | Description | Default |
|----------|-------------|---------|
| `K8S_DEPLOYMENT` | Deployment name | (required) |
| `K8S_NAMESPACE` | Namespace | `default` |
| `K8S_CONTEXT` | Kubectl context | (current) |
| `K8S_CONFIGMAP` | ConfigMap for env vars | (optional) |

#### AWS Lambda
| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_LAMBDA_FUNCTION` | Function name | (required) |
| `AWS_REGION` | AWS region | `us-east-1` |
| `AWS_PROFILE` | AWS CLI profile | (default) |

#### AWS ECS/Fargate
| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_ECS_CLUSTER` | ECS cluster name | (required) |
| `AWS_ECS_SERVICE` | ECS service name | (required) |
| `AWS_REGION` | AWS region | `us-east-1` |
| `AWS_PROFILE` | AWS CLI profile | (default) |

#### Azure Functions
| Variable | Description | Default |
|----------|-------------|---------|
| `AZURE_FUNCTION_APP` | Function app name | (required) |
| `AZURE_RESOURCE_GROUP` | Resource group | (required) |
| `AZURE_SUBSCRIPTION` | Subscription ID | (optional) |

#### Heroku
| Variable | Description | Default |
|----------|-------------|---------|
| `HEROKU_APP` | App name | (from git remote) |
| `HEROKU_REMOTE` | Git remote name | `heroku` |

#### Fly.io
| Variable | Description | Default |
|----------|-------------|---------|
| `FLY_APP` | App name | (from fly.toml) |

#### Render
| Variable | Description | Default |
|----------|-------------|---------|
| `RENDER_SERVICE_ID` | Service ID | (required) |
| `RENDER_API_KEY` | API key | (required) |

#### Netlify
| Variable | Description | Default |
|----------|-------------|---------|
| `NETLIFY_SITE_ID` | Site ID | (from .netlify/) |
| `NETLIFY_AUTH_TOKEN` | Auth token | (from CLI) |

### Local Env File Search Order

1. `.env.production`
2. `.env`
3. `.env.local`
4. `functions/.env`

## Adding Custom Providers

Create a new file in `providers/` implementing these functions:

```bash
#!/bin/bash
# providers/my-provider.sh

PROVIDER_NAME="My Provider"
PROVIDER_ID="my-provider"

# Return 0 if this project uses this provider
detect() {
  [ -f "${PROJECT_DIR}/my-config.json" ] && return 0
  return 1
}

# Validate required configuration, return non-zero on error
validate_config() {
  [ -z "$MY_API_KEY" ] && echo "Error: MY_API_KEY not set" && return 1
  return 0
}

# Return 0 if service exists
service_exists() {
  my-cli status &>/dev/null
}

# Output KEY=VALUE per line to stdout
fetch_live_env() {
  my-cli env list | grep "=" || true
}

# Output secret references to stdout
fetch_live_secrets() {
  my-cli secrets list || true
}

# Deploy with merged env vars
# Args: env_vars secrets vars_to_remove source_dir
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  # Set env vars, remove old ones, deploy
  my-cli deploy --env "$env_vars" --source "$source_dir"
}

# Print provider info
print_info() {
  echo "Provider: $PROVIDER_NAME"
}
```

## Examples

See the `examples/` directory for sample configurations:

- `examples/gcp-cloud-run/` - Cloud Run with Firebase backend
- `examples/vercel-nextjs/` - Next.js on Vercel
- `examples/cloudflare-workers/` - Cloudflare Workers API

## Security

This hook is designed with security in mind:

### What We Protect Against

| Threat | Mitigation |
|--------|------------|
| **Secrets in logs** | Env var values are NEVER printed - only key names and character lengths |
| **Temp file exposure** | Temp files use 600 permissions and are shredded on exit |
| **Command injection** | Array-based command construction (no `eval` of user data) |
| **Unknown var persistence** | `--strict` mode fails on vars not in local .env |
| **Accidental deletions** | Interactive prompt before removing vars; keeps all by default |

### Strict Mode for CI/CD

In CI/CD pipelines, use `--strict` to fail if there are env vars in the live service that aren't defined in your local `.env`:

```bash
deploy.sh --strict
```

This prevents:
- Accidental preservation of vars added by attackers
- Drift between your code and deployed configuration
- Surprise vars that you don't know about

Exit codes:
- `0` - Success
- `2` - Deployment failed
- `3` - Strict mode violation (unknown vars detected)

### Best Practices

1. **Always use `--dry-run` first** to preview changes
2. **Use `--strict` in CI/CD** to enforce env var hygiene
3. **Review vars marked for removal** before confirming deletion
4. **Keep `.env` files out of git** (they contain secrets!)
5. **Use Secret Manager** for sensitive values, not plain env vars

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| **macOS** | ✅ Full | Native bash, tested on 10.15+ |
| **Linux** | ✅ Full | All major distros |
| **Windows (WSL2)** | ✅ Full | Recommended for Windows |
| **Windows (Git Bash)** | ✅ Works | Included with Git for Windows |
| **Windows (native)** | ❌ No | Use WSL2 or Git Bash |

## Windows Setup Guide

This hook requires a bash environment. Windows users have two excellent options:

### Option 1: WSL2 (Recommended)

WSL2 (Windows Subsystem for Linux) provides a full Linux environment inside Windows. This is the best option for developers.

#### Installing WSL2

1. **Open PowerShell as Administrator** and run:
   ```powershell
   wsl --install
   ```

2. **Restart your computer** when prompted

3. **Set up Ubuntu** (or your preferred distro):
   - A terminal window will open after restart
   - Create a username and password
   - You now have a full Linux environment!

4. **Install required tools** in WSL2:
   ```bash
   # Update packages
   sudo apt update && sudo apt upgrade -y

   # Install jq (required)
   sudo apt install -y jq

   # Install cloud CLIs as needed
   # GCP: https://cloud.google.com/sdk/docs/install
   # AWS: sudo apt install -y awscli
   # Azure: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux
   ```

5. **Access your Windows files** from WSL2:
   ```bash
   # Your C: drive is at /mnt/c/
   cd /mnt/c/Users/YourUsername/Projects/your-project
   ```

6. **Install the hook**:
   ```bash
   git clone https://github.com/sterlingsky/claude-deploy-hook.git .claude/hooks
   chmod +x .claude/hooks/deploy.sh .claude/hooks/lib/*.sh .claude/hooks/providers/*.sh
   ```

#### Using Claude Code with WSL2

When using Claude Code on Windows with WSL2:

1. **Open your project in WSL2**:
   ```bash
   cd /mnt/c/Users/YourUsername/Projects/your-project
   ```

2. **Run Claude Code from WSL2 terminal** (if using CLI version)

3. **Or configure VS Code** to use WSL2:
   - Install the "Remote - WSL" extension
   - Click the green button in bottom-left → "New WSL Window"
   - Open your project folder

### Option 2: Git Bash

Git Bash comes bundled with [Git for Windows](https://git-scm.com/download/win) and provides a bash environment.

#### Installing Git Bash

1. **Download Git for Windows**: https://git-scm.com/download/win

2. **Run the installer** with these recommended options:
   - ✅ Git Bash Here (adds right-click menu)
   - ✅ Use Git from the Windows Command Prompt
   - ✅ Use bundled OpenSSH
   - ✅ Use MinTTY terminal

3. **Install jq for Git Bash**:
   ```bash
   # Download jq
   curl -L -o /usr/bin/jq.exe https://github.com/stedolan/jq/releases/latest/download/jq-win64.exe
   ```

4. **Install the hook**:
   ```bash
   # Right-click in your project folder → "Git Bash Here"
   git clone https://github.com/sterlingsky/claude-deploy-hook.git .claude/hooks
   ```

#### Git Bash Limitations

Git Bash works well but has some limitations compared to WSL2:

| Feature | Git Bash | WSL2 |
|---------|----------|------|
| Basic deployment | ✅ | ✅ |
| Environment variables | ✅ | ✅ |
| Interactive prompts | ✅ | ✅ |
| Complex shell scripts | ⚠️ Some issues | ✅ |
| Native Linux tools | ❌ | ✅ |
| Performance | Good | Excellent |

### Windows PATH Configuration

Some cloud CLIs need to be accessible from bash. Add them to your PATH:

#### For WSL2
Add to `~/.bashrc`:
```bash
# If using Windows-installed CLIs (not recommended, install in WSL instead)
export PATH="$PATH:/mnt/c/Program Files/Google/Cloud SDK/google-cloud-sdk/bin"
```

#### For Git Bash
The Windows PATH is usually inherited. If not, add to `~/.bashrc`:
```bash
export PATH="$PATH:/c/Program Files/Google/Cloud SDK/google-cloud-sdk/bin"
export PATH="$PATH:/c/Program Files/nodejs"
```

### Troubleshooting Windows Issues

#### "Command not found" errors
```bash
# Check if the command is in PATH
which gcloud  # or aws, kubectl, etc.

# If not found, install in WSL2:
# GCP: curl https://sdk.cloud.google.com | bash
# AWS: sudo apt install awscli
```

#### Line ending issues (CRLF vs LF)
```bash
# If you see errors like "^M: command not found"
# Fix line endings:
sed -i 's/\r$//' .claude/hooks/*.sh
sed -i 's/\r$//' .claude/hooks/lib/*.sh
sed -i 's/\r$//' .claude/hooks/providers/*.sh

# Prevent future issues - configure git:
git config --global core.autocrlf input
```

#### Permission denied errors
```bash
# Make scripts executable
chmod +x .claude/hooks/deploy.sh
chmod +x .claude/hooks/lib/*.sh
chmod +x .claude/hooks/providers/*.sh
```

#### WSL2 can't find Windows files
```bash
# Windows drives are mounted at /mnt/
ls /mnt/c/  # C: drive
ls /mnt/d/  # D: drive

# Your user folder:
cd /mnt/c/Users/$USER/
```

### Windows Quick Start Checklist

- [ ] Install WSL2 (`wsl --install`) or Git for Windows
- [ ] Install `jq` in your bash environment
- [ ] Install cloud provider CLIs (gcloud, aws, etc.)
- [ ] Clone the hook into your project
- [ ] Make scripts executable with `chmod +x`
- [ ] Configure `.claude/settings.json`
- [ ] Test with `./deploy.sh --help`

## Requirements

### System Requirements
- **Bash 3.2+** (macOS default) or **Bash 4.0+** (Linux, WSL2)
- **jq** - JSON parsing (install: `brew install jq` / `apt install jq`)
- **curl** - HTTP requests (usually pre-installed)

### Provider-Specific CLIs

Install only the CLIs for providers you use:

| Provider | CLI | Install Command |
|----------|-----|-----------------|
| GCP | `gcloud` | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| Firebase | `firebase` | `npm install -g firebase-tools` |
| AWS | `aws` | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| AWS SAM | `sam` | [docs.aws.amazon.com/sam](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) |
| Azure | `az` | [docs.microsoft.com/cli/azure](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Azure Functions | `func` | `npm install -g azure-functions-core-tools@4` |
| Vercel | `vercel` | `npm install -g vercel` |
| Cloudflare | `wrangler` | `npm install -g wrangler` |
| Railway | `railway` | `npm install -g @railway/cli` |
| Kubernetes | `kubectl` | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| Helm | `helm` | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| Heroku | `heroku` | `npm install -g heroku` |
| Fly.io | `flyctl` | [fly.io/docs/hands-on/install-flyctl](https://fly.io/docs/hands-on/install-flyctl/) |
| Netlify | `netlify` | `npm install -g netlify-cli` |
| Render | - | Uses API (no CLI needed) |

## Testing

The project includes a comprehensive test suite using [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

### Running Tests

```bash
# Run all tests
./tests/run_tests.sh

# Run with verbose output
./tests/run_tests.sh -v

# Run specific test file
./tests/run_tests.sh tests/provider_detection.bats
```

### Test Structure

```
tests/
├── run_tests.sh           # Test runner
├── test_helper.bash       # Shared test utilities
├── provider_detection.bats # Provider auto-detection tests
├── env_comparison.bats    # Env var comparison tests
├── deploy_hook.bats       # Main deploy.sh tests
├── mocks/                 # Mock CLI tools
│   ├── aws
│   ├── gcloud
│   ├── firebase
│   ├── kubectl
│   ├── vercel
│   ├── heroku
│   ├── flyctl
│   └── curl
└── fixtures/              # Test fixtures
```

### Testing Without Cloud Accounts

The test suite uses mock CLI tools that simulate real responses. This allows you to:

1. **Test provider detection** - Verify projects are correctly identified
2. **Test env var comparison** - Verify add/update/remove logic
3. **Test security features** - Verify secrets aren't leaked
4. **Test dry-run mode** - Verify no actual deployments occur

### Adding Tests for New Providers

1. Create a mock CLI in `tests/mocks/your-cli`
2. Add detection tests to `provider_detection.bats`
3. Add a project creation helper to `test_helper.bash`

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests if applicable
4. Submit a pull request

### Adding a Provider

1. Create `providers/your-provider.sh`
2. Implement required functions (see "Adding Custom Providers")
3. Add documentation to README
4. Submit PR
