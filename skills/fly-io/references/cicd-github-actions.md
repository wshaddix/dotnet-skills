# Fly.io CI/CD with GitHub Actions

## Table of Contents

- [Basic Deployment Workflow](#basic-deployment-workflow)
- [Deploy Tokens](#deploy-tokens)
- [Review Apps (PR Previews)](#review-apps-pr-previews)
- [Multi-App / Monorepo Deploys](#multi-app--monorepo-deploys)
- [Deployment Strategies in CI](#deployment-strategies-in-ci)

## Basic Deployment Workflow

### Setup Steps

1. Generate a deploy token: `fly tokens create deploy -x 999999h`
2. Add `FLY_API_TOKEN` repository secret in GitHub Settings -> Secrets and variables -> Actions
3. Create workflow file:

```yaml
# .github/workflows/fly.yml
name: Fly Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    name: Deploy app
    runs-on: ubuntu-latest
    concurrency: deploy-group
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

Ensure `fly.toml` is committed to the repository (do not `.gitignore` it when using GitHub Actions).

### With Environment Secrets

```yaml
deploy:
  name: Deploy app
  runs-on: ubuntu-latest
  environment: production
  steps:
    - uses: actions/checkout@v4
    - uses: superfly/flyctl-actions/setup-flyctl@master
    - run: flyctl deploy --remote-only
      env:
        FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

## Deploy Tokens

**App-specific deploy token** (recommended for CI):

```bash
fly tokens create deploy -x 999999h     # Long-lived deploy token for one app
```

Copy the entire output including `FlyV1 ` prefix and space.

**Org-wide auth token** (manages all apps):

```bash
fly auth token                           # Full-access token
```

Use app-specific deploy tokens in CI for least-privilege access.

## Review Apps (PR Previews)

Deploy ephemeral preview apps for each pull request:

```yaml
# .github/workflows/fly-review.yml
name: Fly Review App
on:
  pull_request:
    types: [opened, reopened, synchronize, closed]

env:
  FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

jobs:
  review:
    runs-on: ubuntu-latest
    concurrency:
      group: pr-${{ github.event.number }}
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master

      - name: Deploy review app
        if: github.event.action != 'closed'
        run: |
          APP_NAME="pr-${{ github.event.number }}-my-app"
          flyctl apps create $APP_NAME --org my-org || true
          flyctl deploy --remote-only --app $APP_NAME --config fly.review.toml
          echo "Deployed to https://$APP_NAME.fly.dev" >> $GITHUB_STEP_SUMMARY

      - name: Destroy review app
        if: github.event.action == 'closed'
        run: |
          APP_NAME="pr-${{ github.event.number }}-my-app"
          flyctl apps destroy $APP_NAME --yes || true
```

Create a `fly.review.toml` with smaller Machine sizes and fewer instances for cost efficiency.

## Multi-App / Monorepo Deploys

Deploy multiple apps from one repo using path filters:

```yaml
name: Deploy Services
on:
  push:
    branches: [main]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      api: ${{ steps.filter.outputs.api }}
      web: ${{ steps.filter.outputs.web }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v2
        id: filter
        with:
          filters: |
            api:
              - 'services/api/**'
            web:
              - 'services/web/**'

  deploy-api:
    needs: detect-changes
    if: needs.detect-changes.outputs.api == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only --config services/api/fly.toml
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

  deploy-web:
    needs: detect-changes
    if: needs.detect-changes.outputs.web == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only --config services/web/fly.toml
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

## Deployment Strategies in CI

### Rolling Deploy (Default)

No extra config needed. Machines replaced one-by-one.

### Canary Deploy

```toml
# fly.toml
[deploy]
  strategy = "canary"
```

One new Machine deployed first. If health checks pass, remaining Machines are updated via rolling. If the canary fails, deploy halts. Cannot be used with volumes.

### Blue-Green Deploy

```toml
# fly.toml
[deploy]
  strategy = "bluegreen"
```

New Machines boot alongside existing ones. Traffic migrates after all health checks pass. Requires health checks to be configured. Cannot be used with volumes.

### Staging Before Production

```yaml
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only --app my-app-staging
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN_STAGING }}

  smoke-test:
    needs: deploy-staging
    runs-on: ubuntu-latest
    steps:
      - run: curl -f https://my-app-staging.fly.dev/health

  deploy-production:
    needs: smoke-test
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only --app my-app
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN_PROD }}
```

### Database Migrations in CI

Use the `release_command` in fly.toml to run migrations before deployment:

```toml
[deploy]
  release_command = "bin/rails db:migrate"
  release_command_timeout = "10m"
```

The release command runs in a temporary Machine with your app's image. It does NOT have access to volumes. Non-zero exit code aborts the deploy.
