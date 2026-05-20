---
name: aws-cli
description: Running AWS CLI commands and debugging AWS access issues across any project. TRIGGER when the user wants to query / mutate AWS resources (CloudWatch logs, ECS, S3, IAM, EC2, Lambda, RDS, Secrets Manager, etc.) or hits AWS auth / region / permission errors. Covers profile-first discipline, the aws-broker wrapper (when present), region awareness, --dry-run for destructive ops, and recovery from common errors (UnauthorizedOperation, AccessDenied, NoCredentialsError, missing region).
---

# AWS CLI

Most AWS CLI failures come from **wrong profile, wrong region, or guessing command syntax**. This skill enforces profile-first discipline.

## Pre-flight Checklist (do every time)

Before running any AWS command:

1. **Identify which profile** — never assume. Check the project's CLAUDE.md / README for the right profile, or run `aws-broker list` (if available) / `aws configure list-profiles` to see options.
2. **Confirm caller identity** — `aws-broker <profile> sts get-caller-identity` (or `aws sts get-caller-identity --profile <profile>`). This catches "wrong account" mistakes before doing anything destructive.
3. **Specify the region explicitly** — most CLI commands need `--region` if the profile config doesn't pin one. Defaults differ per service.
4. **For destructive operations, use `--dry-run` first** when supported (EC2, IAM modify ops). For services without `--dry-run`, run the read-only equivalent (`describe-*` / `list-*`) first to confirm the target.

Skipping (1)–(2) is the most common cause of "AccessDenied" / "ResourceNotFound" / "wrong account!?" panics.

## The `aws-broker` Wrapper (when available)

Some environments ship an `aws-broker` wrapper that runs `aws-cli` inside a docker container with `~/.aws/` mounted. Form: `aws-broker <profile> <aws-args...>`. Use it whenever it's installed (`command -v aws-broker`); fall back to bare `aws --profile <profile>` only when the wrapper is missing.

```bash
# Preferred:
aws-broker red-codens-prod logs tail "/ecs/red-codens-prod/celery-worker" --since 1h

# Fallback if no wrapper:
aws --profile red-codens-prod logs tail "/ecs/red-codens-prod/celery-worker" --since 1h
```

Helpers (when wrapper available):
- `aws-broker list` — show configured profiles
- `aws-broker login <profile>` — SSO device-code login
- `aws-broker --help` — full usage

## Region Defaults (project-specific)

The region usually comes from `~/.aws/config` per profile. If it's not pinned there, append `--region <region>` to every command. Common Codens defaults are documented per project in their CLAUDE.md.

If you see `You must specify a region. You can also configure your region by running "aws configure"`, the profile has no default region — pass `--region` explicitly. Do NOT silently assume `us-east-1`.

## Common Command Recipes

These are read-only / safe by default. Substitute real profile + resource names per project.

### CloudWatch logs
```bash
# Tail a log group (last hour, follow mode)
aws-broker <profile> logs tail "/ecs/<service>" --since 1h --follow

# One-shot last N minutes
aws-broker <profile> logs tail "/ecs/<service>" --since 30m

# Filter by pattern
aws-broker <profile> logs filter-log-events \
  --log-group-name "/ecs/<service>" \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000
```

### ECS
```bash
# Service status (desired vs running count)
aws-broker <profile> ecs describe-services \
  --cluster <cluster-name> \
  --services <service-name> \
  --query 'services[].{name:serviceName,status:status,desired:desiredCount,running:runningCount}'

# Latest task definition
aws-broker <profile> ecs describe-task-definition --task-definition <family> --query 'taskDefinition.revision'

# Force re-deploy (no task def change)
aws-broker <profile> ecs update-service --cluster <c> --service <s> --force-new-deployment
```

### S3
```bash
# List buckets
aws-broker <profile> s3api list-buckets --query 'Buckets[].Name'

# Sync local → S3 (dry-run first!)
aws-broker <profile> s3 sync ./dist s3://<bucket>/path/ --dryrun
aws-broker <profile> s3 sync ./dist s3://<bucket>/path/

# Copy single file
aws-broker <profile> s3 cp ./file.json s3://<bucket>/key
```

### IAM (read-only checks)
```bash
# What roles can my user assume?
aws-broker <profile> iam list-attached-user-policies --user-name <username>

# What does a role allow?
aws-broker <profile> iam get-role-policy --role-name <role> --policy-name <policy>
```

### Secrets Manager
```bash
# List secret names (do NOT list values en-masse)
aws-broker <profile> secretsmanager list-secrets --query 'SecretList[].Name'

# Get a single secret value
aws-broker <profile> secretsmanager get-secret-value --secret-id <name> --query SecretString --output text
```

### EC2 (with --dry-run for destructive)
```bash
# List instances
aws-broker <profile> ec2 describe-instances --query 'Reservations[].Instances[].{id:InstanceId,state:State.Name,ip:PublicIpAddress}'

# Stop (always --dry-run first to confirm permission + target)
aws-broker <profile> ec2 stop-instances --instance-ids i-xxx --dry-run
aws-broker <profile> ec2 stop-instances --instance-ids i-xxx
```

## Common Errors and Recovery

| Error | Likely cause | Fix |
|-------|-------------|-----|
| `Unable to locate credentials` | Profile typo / SSO token expired | `aws-broker list` to see real profile names; `aws-broker login <profile>` if SSO expired |
| `An error occurred (UnauthorizedOperation)` (EC2) | Permission issue, but possibly silent — re-check region too | Compare profile's IAM policy; re-run with `--region <region>` explicit |
| `An error occurred (AccessDenied)` (S3) | Wrong profile / bucket policy / no permission for that resource | `sts get-caller-identity` to confirm account; re-check profile |
| `You must specify a region` | Profile has no default region | Pass `--region <region>` explicitly |
| `An error occurred (ResourceNotFound)` (logs / ECS) | Wrong profile (resource exists in a different account!), wrong region, or wrong name | Confirm caller identity + region. Don't blindly retry. |
| `expired token / invalid_grant` (SSO) | Token expired (SSO sessions are 8-12 hours) | `aws-broker login <profile>` to refresh |
| `An error occurred (Throttling)` | Hitting API rate limits | Add backoff: `for i in 1 2 3; do CMD && break || sleep 5; done`. Consider `--no-paginate` to avoid sweeping list ops |
| `Could not connect to the endpoint URL` | Region typo (e.g., `us-east1` instead of `us-east-1`) | Use exact region name with hyphen |

## Anti-Patterns

- **Don't iterate guessing** — if a command fails twice for related reasons, STOP and run `sts get-caller-identity` + `aws configure list` to recheck assumptions.
- **Don't run destructive ops without confirming target** — always read-only first (`describe`, `list`).
- **Don't use `aws --profile X --region Y` when you could embed those in `~/.aws/config`** — but DO pass them explicitly when the profile lacks a default.
- **Don't paste credentials into terminal** — use `aws sso login` / `aws configure sso` flows. Keys in env vars / commit history is a security incident.
- **Don't loop 5+ times retrying a failing command** — same input = same failure. Diagnose, then act.

## Project-Specific Profile Names

The actual profile-to-account mapping lives in each project's CLAUDE.md (e.g., `red-codens-prod`, `green-codens-prod`, `opsguide`, `kataren-prod`). When you don't know which profile to use:

1. Check the current repo's `CLAUDE.md`
2. Run `aws-broker list` to see what's configured
3. Ask the user if neither resolves it
