#!/bin/bash

# Tenant Instance User Data Script
# This script sets up a tenant messaging instance with Docker and WhatsApp server

set -e

# Variables from template
WHATSAPP_SERVER_IMAGE_URI="${whatsapp_server_image_uri}"
TENANTS_TABLE_NAME="${tenants_table_name}"
AWS_REGION="${aws_region}"

# Log everything
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting tenant instance setup at $(date)"

# Update system
echo "Updating system packages..."
dnf update -y

# Install Docker
echo "Installing Docker..."
dnf install -y docker
systemctl start docker
systemctl enable docker

# Install AWS CLI v2 (if not already installed)
echo "Installing AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws/
fi

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
dnf install -y amazon-cloudwatch-agent

# Get instance metadata
echo "Getting instance metadata..."
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

echo "Instance ID: $INSTANCE_ID"
echo "Availability Zone: $AVAILABILITY_ZONE"

# Create directories for WhatsApp server
echo "Creating application directories..."
mkdir -p /opt/whatsapp-server
mkdir -p /opt/whatsapp-server/profiles
mkdir -p /opt/whatsapp-server/tokens
mkdir -p /opt/whatsapp-server/uploads

# Set permissions
chown -R ec2-user:ec2-user /opt/whatsapp-server

# Create docker-compose file for WhatsApp server
echo "Creating Docker Compose configuration..."
cat > /opt/whatsapp-server/docker-compose.yml << EOF
version: '3.8'
services:
  whatsapp-server:
    image: $WHATSAPP_SERVER_IMAGE_URI
    container_name: whatsapp-server
    ports:
      - "21465:21465"
    volumes:
      - ./profiles:/app/whatsapp_profiles
      - ./tokens:/app/whatsapp_tokens
      - ./uploads:/app/uploads
    environment:
      - NODE_ENV=production
      - PORT=21465
      - INSTANCE_ID=$INSTANCE_ID
      - TENANTS_TABLE_NAME=$TENANTS_TABLE_NAME
      - AWS_REGION=$AWS_REGION
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:21465/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

# Create systemd service for WhatsApp server
echo "Creating systemd service..."
cat > /etc/systemd/system/whatsapp-server.service << EOF
[Unit]
Description=WhatsApp Server
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/whatsapp-server
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0
User=ec2-user
Group=ec2-user

[Install]
WantedBy=multi-user.target
EOF

# Install docker-compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Pull the WhatsApp server image
echo "Pulling WhatsApp server image..."
docker pull $WHATSAPP_SERVER_IMAGE_URI

# Enable and start the service
echo "Enabling and starting WhatsApp server service..."
systemctl daemon-reload
systemctl enable whatsapp-server.service
systemctl start whatsapp-server.service

# Wait for service to be ready
echo "Waiting for WhatsApp server to be ready..."
sleep 30

# Check service status
echo "Checking service status..."
systemctl status whatsapp-server.service

# Create a simple health check script
cat > /opt/whatsapp-server/health-check.sh << 'EOF'
#!/bin/bash
# Health check script for WhatsApp server
curl -f http://localhost:21465/health > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "$(date): WhatsApp server is healthy"
    exit 0
else
    echo "$(date): WhatsApp server is not responding"
    exit 1
fi
EOF

chmod +x /opt/whatsapp-server/health-check.sh

# Set up cron job for health checks (every 5 minutes)
echo "*/5 * * * * /opt/whatsapp-server/health-check.sh >> /var/log/whatsapp-health.log 2>&1" | crontab -u ec2-user -

# Update DynamoDB with instance ready status
echo "Updating DynamoDB with instance ready status..."
aws dynamodb put-item \
    --region $AWS_REGION \
    --table-name $TENANTS_TABLE_NAME \
    --item '{
        "PK": {"S": "instance"},
        "SK": {"S": "'$INSTANCE_ID'"},
        "status": {"S": "ready"},
        "instanceId": {"S": "'$INSTANCE_ID'"},
        "availabilityZone": {"S": "'$AVAILABILITY_ZONE'"},
        "readyTimestamp": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
    }' || echo "Failed to update DynamoDB - continuing anyway"

echo "Tenant instance setup completed at $(date)"
echo "WhatsApp server should be available at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):21465"