# Implementation Report: TravelMemory MERN Deployment via Terraform and Ansible

## 1. Objective

Deploy the [TravelMemory](https://github.com/Rahul-17personal/TravelMemory) MERN
application to AWS using Terraform for infrastructure provisioning and Ansible
for configuration management and application deployment.

## 2. Architecture

```
                              Internet
                                 |
                          Internet Gateway
                                 |
                    ┌─────────────────────────┐
                    │   Public Subnet          │
                    │   10.0.1.0/24            │
                    │                          │
                    │   EC2: web-server        │
                    │   - Node.js 20 + npm     │
                    │   - React (built static) │
                    │   - Express backend (pm2)│
                    │   - nginx (reverse proxy)│
                    │   Public IP: 13.206.249.28│
                    └───────────┬──────────────┘
                                │ NAT Gateway (outbound only)
                                │
                    ┌───────────▼──────────────┐
                    │   Private Subnet          │
                    │   10.0.2.0/24             │
                    │                           │
                    │   EC2: db-server          │
                    │   - MongoDB 7.0           │
                    │   - Auth enabled          │
                    │   Private IP: 10.0.2.233  │
                    │   (no public IP)          │
                    └───────────────────────────┘

VPC CIDR: 10.0.0.0/16   |   Region: ap-south-1   |   AZ: ap-south-1a
```

### Component interaction

1. A browser requests `http://<web-public-ip>/`. nginx on the web server
   serves the pre-built React static files (`frontend/build`) for any
   non-API route, and falls back to `index.html` for React Router's
   client-side routing.
2. The React app makes API calls (e.g. `POST /trip`) directly to the
   Express backend, which pm2 keeps running as a background process on
   the web server.
3. The Express backend connects to MongoDB using a connection string
   pointing at the database server's **private IP** (10.0.2.233) — this
   traffic never leaves the VPC.
4. The database server has no public IP. It reaches the internet only
   through the NAT Gateway (needed for `apt` package installs during
   provisioning); inbound access is restricted to the web server's
   security group only, on port 27017 (MongoDB) and 22 (SSH, used as a
   bastion hop during configuration).

## 3. Infrastructure (Terraform)

| Resource | Purpose |
|---|---|
| `aws_vpc` | Isolated network, 10.0.0.0/16 |
| `aws_subnet` (public, private) | Segregates web tier from data tier |
| `aws_internet_gateway` | Public subnet's route to the internet |
| `aws_nat_gateway` + `aws_eip` | Lets the private subnet reach the internet outbound (package installs) without being reachable inbound |
| `aws_route_table` (x2) + associations | Routes public subnet traffic via IGW, private subnet traffic via NAT |
| `aws_instance.web` | t3.micro in the public subnet, public IP assigned |
| `aws_instance.db` | t3.micro in the private subnet, no public IP |
| `aws_security_group.web` | Allows SSH from admin IP only, HTTP/HTTPS from anywhere, dev ports 3000-3001 for testing |
| `aws_security_group.db` | Allows MongoDB (27017) and SSH (22) only from the web security group |
| `aws_iam_role` + `aws_iam_instance_profile` | Attaches `AmazonSSMManagedInstanceCore` to both instances as an SSH fallback |
| `local_file.ansible_inventory` | Auto-generates `ansible/inventory.ini` from the instances' resolved IPs immediately after apply |

`terraform apply` output:
```
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.

Outputs:
db_private_ip  = "10.0.2.233"
web_private_ip = "10.0.1.57"
web_public_ip  = "13.206.249.28"
```

## 4. Configuration and Deployment (Ansible)

Two roles, run against the auto-generated inventory:

**`database` role** (target: private DB instance, reached via an SSH
`ProxyCommand` hop through the web server, since it has no public IP):
- Installs MongoDB 7.0 from the official MongoDB apt repository.
- Starts and enables the `mongod` service.
- Creates an admin user and an application-scoped user/database via
  `mongosh` (see Issue 3 below for why this replaced the original
  module-based approach).
- Enables `authorization` in `mongod.conf`.
- Configures `ufw` to allow only SSH and MongoDB traffic from the VPC
  CIDR, then enables it with a default-deny policy.
- Disables root SSH login.

**`webserver` role** (target: public web instance):
- Installs Node.js 20.x and npm via the NodeSource repository.
- Installs `pm2` globally as the process manager.
- Clones the TravelMemory fork and installs backend + frontend
  dependencies.
- Writes the backend's `.env` with the MongoDB connection string,
  pointing at the database server's private IP.
- Builds the React frontend for production (`npm run build`).
- Starts the Express backend under `pm2`, saves the process list, and
  configures `pm2` to restart on boot.
- Configures nginx to serve the built frontend and reverse-proxy `/api/`
  to the backend.
- Configures `ufw` (SSH + HTTP/HTTPS) and disables root SSH login.

Final run result:
```
PLAY RECAP
10.0.2.233     : ok=16  changed=8   unreachable=0  failed=0
13.206.249.28  : ok=23  changed=22  unreachable=0  failed=0
```

## 5. Issues encountered and resolutions

This section documents the real problems hit during this deployment and
how each was diagnosed and fixed — useful both as a record and as a
troubleshooting reference for future runs.

**Issue 1 — Ansible not found in PowerShell.**
Ansible was correctly installed inside WSL, but commands were being run
from a native Windows PowerShell prompt, where Ansible cannot run
natively (it requires a Linux/WSL/macOS environment). *Fix:* run all
`ansible`/`ansible-playbook` commands from WSL, accessing the Windows
project folder via its `/mnt/d/...` mount point. Terraform, which does
support Windows natively, was kept running from PowerShell.

**Issue 2 — `key_name` mismatch and trailing `.pem`.**
The initial `terraform.tfvars` referenced a key pair name
(`key1.pem`) that didn't exist in the AWS account, and a later attempt
included the `.pem` extension in `key_name`. AWS's `key_name` field is
the *name of the registered key pair*, not a filename, and never
includes `.pem`. This was caught in `terraform plan` output before any
resources were created. *Fix:* created a dedicated key pair
(`travelmemory-key`, no spaces, no extension) in the correct region
(`ap-south-1`), downloaded the `.pem` once, and referenced the bare
name in `terraform.tfvars`.

**Issue 3 — `community.mongodb.mongodb_user` module failure.**
The `Create MongoDB admin user` task first failed with
`ModuleNotFoundError: No module named 'pymongo'` (the target host's
Python lacked the library the module depends on). After installing
`pymongo` via `pip`, the same task then failed with a second, unrelated
error: `'RawConfigParser' object has no attribute 'readfp'` — a known
compatibility issue between the installed version of the
`community.mongodb` Ansible collection and the environment's Python.
*Fix:* rather than chase collection/library version pinning, the user
creation tasks were rewritten to shell out directly to `mongosh`
(MongoDB's official shell, bundled with the `mongodb-org` install),
using idempotent JavaScript (`if (!db.getUser(...)) { createUser(...) }`)
so re-running the playbook doesn't recreate users that already exist.

**Issue 4 — Frontend calling `localhost` instead of the server.**
The app loaded, but submitting a form failed in the browser console with
`AxiosError: Network Error` / `ERR_CONNECTION_REFUSED` against
`http://localhost:3001/trip`. The React app's API base URL
(`frontend/src/url.js`) was hardcoded to `localhost`, which — since this
code executes in the *user's browser*, not on the server — pointed
every visitor's request back at their own machine rather than the EC2
instance. *Fix:* updated `url.js` to point at the web server's public
IP and port, then re-ran `npm run build` to bake the corrected URL into
the static bundle, and reloaded nginx.

## 6. Testing

- Confirmed SSH/Ansible connectivity to both hosts independently via
  `ansible -i inventory.ini web -m ping` and
  `ansible -i inventory.ini db -m ping` before running the full
  playbook.
- After deployment, loaded `http://13.206.249.28` in a browser and
  confirmed the TravelMemory UI rendered.
- Submitted a new trip entry through the UI and confirmed it saved
  successfully after the frontend URL fix, verifying the full chain:
  React → nginx → Express (pm2) → MongoDB (private subnet).

*(Insert your screenshots/video here for submission.)*

## 7. Deliverables checklist

- [x] Terraform scripts for AWS infrastructure setup (`terraform/`)
- [x] Ansible playbooks for configuration and deployment (`ansible/`)
- [x] This implementation report (`REPORT.md`)
- [ ] Screenshots/video of the working application
- [ ] Repository link submitted via Vlearn

## 8. Cleanup

Infrastructure was torn down after verification with `terraform destroy`
to avoid ongoing AWS charges. See `README.md` for the exact steps.
