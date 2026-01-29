# Deploy

Deploy to cloud with smart environment variable management.

## What This Does

1. Fetches live env vars from your deployed service
2. Compares with local `.env.production` or `.env`
3. Auto-adds new vars, auto-updates changed vars
4. Prompts before removing vars (safe by default)
5. Preserves secrets from live deployment
6. Deploys the new version

## Usage

```bash
# Auto-detect provider and deploy
"$CLAUDE_PROJECT_DIR"/.claude/hooks/deploy.sh

# Specify provider
"$CLAUDE_PROJECT_DIR"/.claude/hooks/deploy.sh --provider=gcp-cloud-run

# Dry run first
"$CLAUDE_PROJECT_DIR"/.claude/hooks/deploy.sh --dry-run
```

## Available Providers

- `gcp-cloud-run` - GCP Cloud Run
- `gcp-firebase-functions` - Firebase Functions (Gen 1 & 2)
- `vercel` - Vercel
- `cloudflare-workers` - Cloudflare Workers
- `cloudflare-pages` - Cloudflare Pages
- `railway` - Railway
