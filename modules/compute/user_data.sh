#!/bin/bash
###############################################################
# user_data.sh
# Bootstrap script for Amazon Linux 2 – installs Apache, PHP,
# the CloudWatch agent, and deploys a demo Flask-style app.
# All template variables are injected by Terraform.
###############################################################
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "=========================================="
echo " Cloud-Project Bootstrap Start"
echo " $(date)"
echo "=========================================="

###############################################################
# 1. System update & package installation
###############################################################
yum update -y
yum install -y httpd php php-mysqlnd wget curl unzip python3 python3-pip

###############################################################
# 2. Install AWS CloudWatch Agent
###############################################################
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# CloudWatch agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "totalcpu": true
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/httpd/access_log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}/httpd/access",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/httpd/error_log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}/httpd/error",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/app.log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}/app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

###############################################################
# 3. Get instance metadata
###############################################################
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

###############################################################
# 4. Deploy the web application (PHP)
###############################################################
cat > /var/www/html/index.php << PHPAPP
<?php
\$project   = "${project_name}";
\$env       = "${environment}";
\$region    = "${aws_region}";
\$s3bucket  = "${s3_bucket_name}";
\$db_host   = "${db_host}";
\$db_name   = "${db_name}";
\$db_user   = "${db_user}";
\$db_pass   = "${db_pass}";

// Test DB connection
\$db_status  = "unknown";
\$db_version = "";
try {
    \$pdo = new PDO(
        "mysql:host=\$db_host;dbname=\$db_name",
        \$db_user, \$db_pass,
        [PDO::ATTR_TIMEOUT => 3, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    \$row = \$pdo->query("SELECT VERSION() AS v")->fetch(PDO::FETCH_ASSOC);
    \$db_version = \$row['v'];
    \$db_status  = "connected";
} catch (Exception \$e) {
    \$db_status = "error: " . \$e->getMessage();
}

// Instance metadata (set by user-data)
\$instance_id = getenv('INSTANCE_ID') ?: file_get_contents('/tmp/instance_id') ?: 'unknown';
\$az          = getenv('AZ')          ?: file_get_contents('/tmp/az')          ?: 'unknown';
\$private_ip  = getenv('PRIVATE_IP')  ?: file_get_contents('/tmp/private_ip')  ?: 'unknown';
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><?= htmlspecialchars(\$project) ?> – Cloud App</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #0f1117;
      --card: #1a1d27;
      --border: #2d3147;
      --accent: #6c63ff;
      --accent2: #3ecf8e;
      --danger: #ff4d6d;
      --text: #e2e8f0;
      --muted: #94a3b8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg);
      color: var(--text);
      font-family: 'Inter', sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 2rem 1rem;
    }
    header {
      text-align: center;
      margin-bottom: 2.5rem;
    }
    header h1 {
      font-size: 2.2rem;
      font-weight: 700;
      background: linear-gradient(135deg, var(--accent), var(--accent2));
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    header p { color: var(--muted); margin-top: .4rem; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 1.2rem;
      width: 100%;
      max-width: 1100px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.4rem;
      transition: transform .2s, box-shadow .2s;
    }
    .card:hover {
      transform: translateY(-3px);
      box-shadow: 0 8px 30px rgba(108,99,255,.15);
    }
    .card h2 {
      font-size: .75rem;
      font-weight: 600;
      letter-spacing: .1em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: .9rem;
    }
    .stat { font-size: 1.05rem; font-weight: 500; margin-bottom: .4rem; }
    .stat span { color: var(--accent2); font-family: monospace; }
    .badge {
      display: inline-block;
      padding: .25rem .7rem;
      border-radius: 999px;
      font-size: .75rem;
      font-weight: 600;
    }
    .badge-green { background: rgba(62,207,142,.15); color: var(--accent2); }
    .badge-red   { background: rgba(255,77,109,.15);  color: var(--danger); }
    .badge-blue  { background: rgba(108,99,255,.15);  color: var(--accent); }
    footer {
      margin-top: 3rem;
      color: var(--muted);
      font-size: .8rem;
      text-align: center;
    }
  </style>
</head>
<body>
  <header>
    <h1>☁️ <?= htmlspecialchars(\$project) ?></h1>
    <p>Scalable &amp; Highly-Available Web Application on AWS</p>
  </header>

  <div class="grid">
    <div class="card">
      <h2>🖥 EC2 Instance</h2>
      <div class="stat">ID: <span><?= htmlspecialchars(\$instance_id) ?></span></div>
      <div class="stat">AZ: <span><?= htmlspecialchars(\$az) ?></span></div>
      <div class="stat">Private IP: <span><?= htmlspecialchars(\$private_ip) ?></span></div>
      <div class="stat">Region: <span><?= htmlspecialchars(\$region) ?></span></div>
    </div>

    <div class="card">
      <h2>🗄 RDS Database</h2>
      <div class="stat">Status:
        <span class="badge <?= \$db_status === 'connected' ? 'badge-green' : 'badge-red' ?>">
          <?= htmlspecialchars(\$db_status) ?>
        </span>
      </div>
      <?php if(\$db_version): ?>
      <div class="stat">MySQL Version: <span><?= htmlspecialchars(\$db_version) ?></span></div>
      <?php endif; ?>
      <div class="stat">Database: <span><?= htmlspecialchars(\$db_name) ?></span></div>
    </div>

    <div class="card">
      <h2>🪣 S3 Bucket</h2>
      <div class="stat">Bucket: <span><?= htmlspecialchars(\$s3bucket) ?></span></div>
      <div class="stat">Usage: <span class="badge badge-blue">Active</span></div>
    </div>

    <div class="card">
      <h2>⚙ Environment</h2>
      <div class="stat">Environment: <span><?= htmlspecialchars(\$env) ?></span></div>
      <div class="stat">Web Server: <span>Apache <?= phpversion() ?></span></div>
      <div class="stat">Time (UTC): <span><?= gmdate('Y-m-d H:i:s') ?> UTC</span></div>
    </div>
  </div>

  <footer>
    <p><?= htmlspecialchars(\$project) ?> · Deployed with Terraform · AWS Multi-AZ Architecture</p>
  </footer>
</body>
</html>
PHPAPP

###############################################################
# 5. Health check endpoint
###############################################################
cat > /var/www/html/health.php << 'HEALTH'
<?php
http_response_code(200);
header('Content-Type: application/json');
echo json_encode([
  'status' => 'healthy',
  'time'   => gmdate('c'),
]);
HEALTH

###############################################################
# 6. Write metadata files for PHP to read
###############################################################
echo "$INSTANCE_ID" > /tmp/instance_id
echo "$AZ"          > /tmp/az
echo "$PRIVATE_IP"  > /tmp/private_ip

###############################################################
# 7. Start & enable Apache
###############################################################
systemctl enable httpd
systemctl start  httpd

echo "=========================================="
echo " Bootstrap Complete: $(date)"
echo "=========================================="
