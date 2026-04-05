# ☁️ Cloud Project – Scalable AWS Web Application with Terraform

> A scalable, secure, and highly-available PHP web application deployed on AWS using **Terraform** as Infrastructure as Code.  
> Implements EC2/ASG, ALB, RDS MySQL, S3, IAM, VPC, CloudWatch, and SNS.

---

## 📐 Architecture Overview

```
Internet
   │
   ▼
[Route 53 (optional)] ──► [ACM TLS Certificate]
   │
   ▼
[Application Load Balancer]  ◄── Public Subnets (us-east-1a, us-east-1b)
   │         │
   ▼         ▼
[EC2 App] [EC2 App]   ◄── Private Subnets – Auto Scaling Group (min=2, max=6)
   │         │
   ▼         ▼
[RDS MySQL Multi-AZ]  [S3 Bucket (files/assets)]   ◄── Private / No Public Access
   │
   ▼
[CloudWatch + SNS Alerts]   [VPC Flow Logs]   [SSM Session Manager]
```

See [`docs/architecture.html`](docs/architecture.html) for the interactive visual diagram.

---

## 🗂 Project Structure

```
cloud_project/
├── main.tf                         # Root module – wires all modules together
├── variables.tf                    # All input variables
├── outputs.tf                      # Key resource outputs (ALB DNS, etc.)
├── terraform.tfvars.example        # Template for your terraform.tfvars
├── .gitignore                      # Excludes state files and secrets
│
├── modules/
│   ├── networking/                 # VPC, subnets, IGW, NAT, route tables, flow logs
│   ├── security/                   # Security groups (ALB, EC2, RDS)
│   ├── iam/                        # EC2 role + instance profile (least-privilege)
│   ├── s3/                         # App bucket + log bucket
│   ├── rds/                        # RDS MySQL Multi-AZ + parameter group
│   ├── compute/                    # ALB, target group, launch template, ASG, scaling
│   │   └── user_data.sh            # EC2 bootstrap: installs Apache, PHP, CW agent
│   └── monitoring/                 # CloudWatch alarms, dashboard, SNS topic
│
├── scripts/
│   ├── deploy.sh                   # Helper: init → validate → plan → apply
│   └── simulate_failure.sh         # Demo EC2 termination + ASG auto-recovery
│
└── docs/
    └── architecture.html           # Interactive architecture diagram
```

---

## ☁️ AWS Services Used

| Service | Role | Why |
|---|---|---|
| **EC2 + ASG** | Web compute layer | Dynamic scaling; auto-replace failed instances |
| **ALB** | Load balancer | Layer-7 routing, health checks, SSL termination |
| **RDS MySQL** | Database backend | Managed Multi-AZ failover, encrypted, auto-backup |
| **S3** | Object storage | Infinitely scalable, durable, encrypted, versioned |
| **VPC** | Network isolation | Public ALB / Private EC2 & RDS for defence-in-depth |
| **NAT Gateway** | Private outbound | Software updates without exposing EC2 to internet |
| **IAM** | Access control | Least-privilege roles per service |
| **CloudWatch** | Observability | Custom metrics, alarms, log groups, dashboard |
| **SNS** | Alerting | Email notifications for CloudWatch alarms |
| **SSM Session Manager** | Secure access | No port 22 / no key pairs needed |
| **Terraform** | IaC | Repeatable, version-controlled infrastructure |
| **GitHub** | VCS | Audit trail, branching, pull-request workflow |

---

## 🚀 Quick Start

### 1. Prerequisites

| Tool | Minimum Version |
|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5 |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2 |
| AWS account + IAM user with sufficient permissions | – |

### 2. Configure AWS credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret, region (us-east-1), and output format (json)
```

### 3. Clone & configure variables

```bash
git clone https://github.com/YOUR_USERNAME/cloud_project.git
cd cloud_project

# Copy the example and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars – at minimum set db_password and alarm_email
```

### 4. Deploy

```bash
# Option A – use the helper script
bash scripts/deploy.sh

# Option B – manual steps
terraform init
terraform validate
terraform plan  -out=tfplan
terraform apply tfplan
```

### 5. Access the application

```bash
terraform output alb_dns_name
# Open http://<alb-dns-name> in your browser
```

---

## 📊 High Availability & Scaling

### Auto Scaling Group

| Parameter | Value |
|---|---|
| Minimum instances | 2 |
| Desired instances | 2 |
| Maximum instances | 6 |
| Health check type | ELB |
| Instance replacement | Rolling (50% min healthy) |

### Scaling Policies

| Policy | Trigger |
|---|---|
| CPU Target Tracking | Scale when avg CPU > 60% |
| Request Count Target | Scale when requests/target > 1000/min |
| Scheduled scale-down | 8 PM UTC (dev cost saving) |
| Scheduled scale-up | 8 AM UTC |

### Simulate EC2 Failure & Auto-Recovery

```bash
bash scripts/simulate_failure.sh us-east-1
```

This script terminates one instance and polls the ASG until the replacement is `InService`, demonstrating auto-recovery.

---

## 🔒 Security Design

| Layer | Control |
|---|---|
| **Network** | ALB in public subnets; EC2 & RDS in private subnets with no public IPs |
| **Security Groups** | ALB-SG (0.0.0.0/0 → 80/443) → EC2-SG (ALB only → 80) → RDS-SG (EC2 only → 3306) |
| **IAM** | EC2 instance profile with only S3 (scoped) + CloudWatch Agent + SSM |
| **Data at rest** | RDS encrypted (AES-256), S3 SSE-S3 |
| **Data in transit** | ALB supports TLS (HTTPS listener when cert provided) |
| **Access** | SSM Session Manager – no port 22 needed |
| **VPC Flow Logs** | All traffic logged to CloudWatch |

---

## 📈 Monitoring & Observability

### CloudWatch Alarms

| Alarm | Threshold | Action |
|---|---|---|
| High CPU | ≥ 70% for 2 min | SNS email |
| Low CPU | ≤ 10% for 15 min | SNS email |
| ALB 5XX errors | ≥ 50 in 1 min | SNS email |
| ALB response time | ≥ 2s average | SNS email |
| Unhealthy hosts | ≥ 1 | SNS email |
| RDS CPU | ≥ 80% for 3 min | SNS email |
| RDS free storage | ≤ 5 GB | SNS email |

### CloudWatch Dashboard

After deployment, access your dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=cloud-project-prod
```

Or from Terraform output:
```bash
terraform output cloudwatch_dashboard_url
```

The dashboard includes:
- ASG average CPU
- ALB request count
- ALB healthy / unhealthy hosts
- ALB 4XX / 5XX errors  
- ALB target response time
- RDS CPU utilization
- RDS free storage space

---

## 💰 Cost Estimation (us-east-1)

| Resource | Quantity | Est. Monthly |
|---|---|---|
| EC2 t3.micro (on-demand) | 2 | ~$15 |
| Application Load Balancer | 1 | ~$16 |
| NAT Gateway (2 AZs) | 2 | ~$64 |
| RDS db.t3.micro Multi-AZ | 1 | ~$25 |
| S3 (10 GB + requests) | – | ~$1 |
| CloudWatch logs & metrics | – | ~$3 |
| **Total estimate** | | **~$124/month** |

> 💡 **Reduce cost for testing**: use a single NAT gateway, set ASG desired=1, and RDS single-AZ.  
> Use the [AWS Pricing Calculator](https://calculator.aws/) for an exact quote.

---

## 🔄 GitHub Workflow

```bash
# Initial setup (already done)
git init
git remote add origin https://github.com/YOUR_USERNAME/cloud_project.git

# Feature development workflow
git checkout -b feature/add-cloudwatch-alarms
# ... make changes ...
git add .
git commit -m "feat: add CloudWatch CPU and 5XX alarms"
git push origin feature/add-cloudwatch-alarms
# Open Pull Request on GitHub
```

### Recommended Branch Strategy

| Branch | Purpose |
|---|---|
| `main` | Production-ready Terraform |
| `dev` | Development / testing changes |
| `feature/*` | Individual features |

---

## 🧹 Destroy (Tear Down)

```bash
terraform destroy
```

> ⚠️ This will permanently delete all resources including the RDS database. Make sure you have backups before running this.

---

## 📎 Architecture Diagram

Open [`docs/architecture.html`](docs/architecture.html) in your browser for a full interactive architecture diagram.

---

## 👥 Contributors

- **Student Name** – Infrastructure design, Terraform code, documentation

---

## 📄 License

This project is submitted as academic coursework. All rights reserved.