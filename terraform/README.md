# Terraform — Codens VPS

3 つの provider を分割管理:

| ディレクトリ | 内容 | 依存 |
|------------|------|------|
| `aws/` | S3 + KMS + IAM + Roles Anywhere + SES (F23) | step-ca root cert (`scripts/step-ca-root.crt`) |
| `cloudflare/` | 11 × Tunnel + Access Application + Policy | members.yml + Google IdP ID |
| `contabo/` | Cloud Firewall + 11 assignment | members.yml |

## State backend

すべて `s3://codens-tfstate-prod` に保存 (Purple Codens AWS, us-east-1)。事前に bucket 作成 + DynamoDB lock table が必要。

```bash
# 一度だけ手動で
aws s3api create-bucket --bucket codens-tfstate-prod --region us-east-1 \
  --profile purple-codens-prod
aws s3api put-bucket-versioning --bucket codens-tfstate-prod \
  --versioning-configuration Status=Enabled --profile purple-codens-prod
aws s3api put-bucket-encryption --bucket codens-tfstate-prod \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --profile purple-codens-prod
aws s3api put-public-access-block --bucket codens-tfstate-prod \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile purple-codens-prod
```

## Apply 順序

1. `aws/` を先に apply (step-ca root cert を `scripts/step-ca-root.crt` に置いてから)
2. terraform output から SMTP credential / Roles Anywhere ARN を取得し Vault / `group_vars/all.yml` に転記
3. SES の DKIM/MAIL FROM DNS records を corevice.com の DNS 管理元に手動追加
4. `cloudflare/` を apply
5. terraform output から tunnel credentials を取得し Vault に転記
6. `contabo/` を apply with `-var=enable_bootstrap_ssh=true` (Ansible bootstrap 用)
7. Ansible bootstrap + harden 完了後、`-var=enable_bootstrap_ssh=false` で再 apply

## 4-eyes review (CI)

- `plans/team-vps-setup/terraform/**` への変更は GitHub branch protection で PR + 1 review 必須
- GitHub Actions が PR 時に `terraform plan` を実行し PR コメントに投稿
- main merge 後の apply は **手動** (カナリア: 1 台 `-target` で先行適用 → 24h → 全台)

## CI 用 IAM ユーザー (将来)

Phase 1 では ops が手元で apply。Phase 2 で GitHub Actions OIDC + 限定 IAM role に移行。
