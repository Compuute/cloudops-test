# cloudops-test

Infrastructure provisioning and deployment for a containerised web application.
Stack: Debian + Docker + Nginx + PostgreSQL + Redis, managed with Ansible and Terraform.

---

## Architecture

```
                        Internet
                           │
                    ┌──────▼──────┐
                    │    Nginx    │  443 / 80
                    │  (TLS, LE)  │
                    └──────┬──────┘
                           │ 127.0.0.1:8000
                    ┌──────▼──────┐
                    │     App     │  Docker — frontend network
                    │  container  │
                    └──────┬──────┘
                           │  backend network (internal: true)
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌──────▼──────┐
       │  PostgreSQL  │          │    Redis    │
       │  via PgBouncer          │             │
       │  port 6432  │          │  port 6379  │
       └─────────────┘          └─────────────┘

       DB server — private subnet only, no public IP
```

**Production: two hosts.** App server has a public IP. DB server lives on a private subnet — unreachable from the internet.
**Staging: one host** running everything.

---

## Repository layout

```
.
├── terraform/
│   ├── providers/
│   │   ├── hetzner/        # Hetzner Cloud (default)
│   │   └── aws/            # AWS — same output interface, swap in environments/
│   └── environments/
│       ├── staging/        # 1x cx22, 14-day backup retention
│       └── production/     # 2x cx32, prevent_destroy=true, 30-day retention
│
├── ansible/
│   ├── playbooks/
│   │   ├── provision.yml   # full server setup — run once per environment
│   │   └── deploy.yml      # deploy new version — rolling, with auto-rollback
│   ├── roles/
│   │   ├── secrets/        # pluggable secrets: ansible-vault | HashiCorp Vault | AWS SSM
│   │   ├── common/         # deploy user, SSH hardening, UFW, journald
│   │   ├── docker/         # Docker Engine 29 + Compose
│   │   ├── postgresql/     # PostgreSQL 18, app user + readonly user
│   │   ├── pgbouncer/      # connection pooling on :6432
│   │   ├── redis/          # Redis 8, RDB + AOF
│   │   ├── nginx/          # Nginx 1.29, TLS, reverse proxy, stub_status
│   │   ├── certbot/        # Let's Encrypt, auto-renewal via systemd timer
│   │   ├── app/            # docker-compose stack + systemd service
│   │   ├── backup/         # hourly pg_dump → S3
│   │   └── monitoring/     # Prometheus + Grafana + node/nginx exporters
│   └── group_vars/all/
│       ├── vars.yml        # all non-secret config
│       ├── vault.yml       # encrypted (ansible-vault) — gitignored
│       └── vault.example.yml
│
└── .github/workflows/
    ├── security.yml        # Trivy + ansible-lint + shellcheck
    ├── molecule.yml        # role tests in Docker containers
    ├── terraform.yml       # plan on PR, posts diff as comment
    └── deploy.yml          # auto → staging, manual + approval → production
```

---

## Getting started

### Prerequisites

```bash
brew install terraform
pip install ansible ansible-lint molecule molecule-plugins[docker]
ansible-galaxy collection install -r ansible/requirements.yml
```

### 1. Provision infrastructure

```bash
cd terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars   # fill in token, ssh key, domain
terraform init && terraform apply
# writes ansible/inventory/staging/hosts.yml automatically
```

### 2. Set up secrets

```bash
cp ansible/group_vars/all/vault.example.yml /tmp/vault.yml
# edit /tmp/vault.yml with real passwords and keys
ansible-vault encrypt /tmp/vault.yml --output ansible/group_vars/all/vault.yml
```

### 3. Provision servers

```bash
cd ansible
ansible-playbook playbooks/provision.yml \
  --inventory inventory/staging \
  --vault-password-file ~/.vault_pass
```

### 4. Deploy

```bash
ansible-playbook playbooks/deploy.yml \
  --inventory inventory/staging \
  --vault-password-file ~/.vault_pass \
  --extra-vars "app_image_tag=v1.0.0"
```

---

## Deployment flow

```
push to main
     │
     ▼
lint + Trivy scan
     │
     ▼
deploy → staging
     ├─ pull code + build image
     ├─ backup DB
     ├─ run migrations (Rails / Django auto-detected)
     ├─ reload app via systemd
     └─ health check
          ├── ✅ pass → done
          └── ❌ fail → auto-rollback to previous image
     │
     ▼
manual trigger → production  (requires GitHub Environment approval)
     └─ same steps, serial: 1 (one host at a time)
```

---

## Secrets

Controlled by `secrets_backend` in `group_vars/all/vars.yml`:

| Value | When to use |
|-------|-------------|
| `ansible_vault` | local dev |
| `vault` | HashiCorp Vault |
| `ssm` | AWS SSM Parameter Store |

Changing backend requires one variable change — nothing else.

---

## Moving to a different cloud

Change the `source` in `terraform/environments/<env>/main.tf`:

```hcl
# Hetzner → AWS
source = "../../providers/aws/compute"   # was: providers/hetzner/compute
```

Output keys are identical across providers. Ansible is cloud-agnostic — no changes needed there.

---

## GitHub Secrets needed

`ANSIBLE_VAULT_PASSWORD`, `SSH_PRIVATE_KEY`, `HCLOUD_TOKEN`,
`TF_STATE_ACCESS_KEY`, `TF_STATE_SECRET_KEY`, `SLACK_WEBHOOK_URL`

---

## Tests

```bash
cd ansible && ansible-lint playbooks/provision.yml
cd ansible/roles/common && molecule test
cd ansible/roles/nginx  && molecule test
```
