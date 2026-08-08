# TravelMemory: Terraform + Ansible Deployment

Deploys the [TravelMemory](https://github.com/Rahul-17personal/TravelMemory) MERN app
to AWS: a public web server (Node/Express + React, behind nginx) and a private
MongoDB server, provisioned with Terraform and configured with Ansible.

## Architecture

```
                         Internet
                            |
                     Internet Gateway
                            |
                     [ Public Subnet ]
                     EC2: web-server (Node/Express, React build, nginx)
                            |
                       NAT Gateway  <-- lets DB reach internet for apt/mongo installs
                            |
                     [ Private Subnet ]
                     EC2: db-server (MongoDB 7.0, auth enabled, bound to VPC only)
```

The DB has **no public IP**. SSH and app traffic to it flow only through the web
server's security group (bastion-style), and MongoDB only accepts connections
from the web server.

## Prerequisites

- AWS account + AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Ansible >= 2.14, plus the Mongo collection: `ansible-galaxy collection install community.mongodb`
- An existing EC2 key pair in your target region (e.g. `ap-south-1`)
- Your public IP: `curl ifconfig.me`

## Step 1 — Terraform: provision infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set key_name and my_ip

terraform init
terraform plan
terraform apply
```

This creates the VPC, subnets, IGW, NAT gateway, route tables, both EC2
instances, security groups, IAM role, and **auto-writes** `../ansible/inventory.ini`
with the correct IPs and a ProxyCommand so Ansible can reach the private DB
instance through the web server.

Take a screenshot of the `terraform apply` output (for your report) — it shows
`web_public_ip`, which is what you'll browse to at the end.

## Step 2 — Ansible: configure and deploy

```bash
cd ../ansible
ansible-galaxy collection install community.mongodb
```

Before running, override the default passwords (don't leave the placeholders):

```bash
ansible-playbook playbook.yml \
  -e mongo_admin_password='YourStrongAdminPass123!' \
  -e mongo_app_password='YourStrongAppPass123!'
```

This runs, in order:
1. **database role** on the private instance — installs MongoDB 7.0, enables
   auth, creates an admin user and an app-scoped user/database, restricts
   ufw to the VPC CIDR, disables root SSH login.
2. **webserver role** on the public instance — installs Node.js 20/npm,
   clones your fork, installs backend + frontend deps, writes the backend
   `.env` with the Mongo connection string (pointing at the DB's private IP),
   builds the React frontend, runs the backend with pm2, and configures
   nginx to serve the frontend and reverse-proxy `/api/` to the backend.

## Step 3 — Verify

Open `http://<web_public_ip>` in your browser — the TravelMemory app should
load, and trips should save/read successfully (confirms frontend ↔ backend ↔
Mongo are all wired correctly). Take screenshots/record a short video for
your deliverables.

Useful checks over SSH:
```bash
ssh -i ~/.ssh/<key>.pem ubuntu@<web_public_ip>
pm2 status
pm2 logs travelmemory-backend
sudo systemctl status nginx
```

## Notes / known gotchas (confirmed during actual deployment)

- **Run Ansible from WSL, not Windows PowerShell.** Ansible doesn't run
  natively on Windows. Terraform can stay in PowerShell; switch to WSL
  for every `ansible`/`ansible-playbook` command, accessing the project
  via its `/mnt/<drive>/...` path.
- **`key_name` in `terraform.tfvars` is the AWS key pair name, not a
  filename** — no `.pem` extension, no spaces. Create the key pair in
  the same region as `aws_region` (default `ap-south-1`).
- **`community.mongodb.mongodb_user` may fail** with a `pymongo` import
  error or a `RawConfigParser`/`readfp` error depending on your
  environment's Python/collection versions. This project's
  `database` role creates users via `mongosh` directly instead, which
  avoids the dependency entirely.
- **The frontend's API base URL is hardcoded** in
  `frontend/src/url.js` (or similar) to `localhost`. Since this code
  runs in the visitor's browser, it must be updated to the web server's
  public IP (or a relative path proxied by nginx) and the frontend
  rebuilt (`npm run build`) before the app can actually save/load data
  remotely.
- `t2.micro` can hit resource limits under load — this project defaults
  to `t3.micro`.


## Cleanup

```bash
cd terraform
terraform destroy
```

## Pushing to GitHub

```bash
git add .
git commit -m "Add Terraform + Ansible deployment for TravelMemory"
git push origin main
```
