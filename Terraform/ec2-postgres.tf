resource "aws_instance" "postgres" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.postgres.id]

  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  user_data_replace_on_change = true

  depends_on = [aws_route.private_nat]

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              echo "=== Waiting for NAT/internet connectivity ==="

              until timeout 5 bash -c '</dev/tcp/1.1.1.1/443' 2>/dev/null; do
                echo "Waiting for internet connectivity..."
                sleep 10
              done

              echo "=== Internet is available ==="

              # ------------------------------------------------------------
              # 1. Find and mount dedicated PostgreSQL EBS volume
              # ------------------------------------------------------------

              echo "=== Waiting for PostgreSQL EBS volume ==="

              DATA_DISK=""

              for i in $(seq 1 60); do
                DATA_DISK=$(
                  lsblk -dpno NAME,TYPE |
                  awk '$2=="disk" && $1 !~ /nvme0n1$/ {print $1; exit}'
                )

                if [ -n "$DATA_DISK" ]; then
                  break
                fi

                echo "Waiting for EBS volume... attempt $i/60"
                sleep 5
              done

              if [ -z "$DATA_DISK" ]; then
                echo "ERROR: PostgreSQL EBS volume was not found."
                lsblk
                exit 1
              fi

              echo "PostgreSQL EBS volume detected: $DATA_DISK"

              # Format only if filesystem does not exist
              if ! blkid "$DATA_DISK" >/dev/null 2>&1; then
                echo "Formatting $DATA_DISK as ext4..."
                mkfs.ext4 -F "$DATA_DISK"
              fi

              mkdir -p /var/lib/postgresql

              mount "$DATA_DISK" /var/lib/postgresql

              POSTGRES_UUID=$(blkid -s UUID -o value "$DATA_DISK")

              if ! grep -q "$POSTGRES_UUID" /etc/fstab; then
                echo "UUID=$POSTGRES_UUID /var/lib/postgresql ext4 defaults,nofail 0 2" \
                  >> /etc/fstab
              fi

              mount -a

              echo "=== PostgreSQL volume mounted ==="
              df -h /var/lib/postgresql

              # ------------------------------------------------------------
              # 2. Update package lists
              # ------------------------------------------------------------

              apt-get update -y

              # ------------------------------------------------------------
              # 3. Install PostgreSQL and required tools
              # ------------------------------------------------------------

              apt-get install -y \
                postgresql \
                curl \
                ca-certificates \
                unzip \
                openssl

              # ------------------------------------------------------------
              # 4. AWS CLI v2
              # ------------------------------------------------------------

              echo "=== Installing AWS CLI v2 ==="

              curl -fsSL \
                "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
                -o /tmp/awscliv2.zip

              unzip -q /tmp/awscliv2.zip -d /tmp
              /tmp/aws/install

              rm -rf /tmp/aws /tmp/awscliv2.zip

              /usr/local/bin/aws --version

              # ------------------------------------------------------------
              # 5. Start PostgreSQL
              # ------------------------------------------------------------

              echo "=== Starting PostgreSQL ==="

              systemctl enable postgresql
              systemctl start postgresql

              # ------------------------------------------------------------
              # 6. Generate PostgreSQL password
              # ------------------------------------------------------------

              echo "=== Generating PostgreSQL password ==="

              DB_PASSWORD=$(openssl rand -hex 32)

              # ------------------------------------------------------------
              # 7. Save password to SSM
              # ------------------------------------------------------------

              echo "=== Saving password to SSM Parameter Store ==="

              until /usr/local/bin/aws ssm put-parameter \
                --region ${var.aws_region} \
                --name "/travel-planner/postgres-password" \
                --type "SecureString" \
                --value "$DB_PASSWORD" \
                --overwrite; do

                echo "Waiting for SSM/IAM..."
                sleep 10
              done

              # ------------------------------------------------------------
              # 8. Configure PostgreSQL
              # ------------------------------------------------------------

              echo "=== Configuring PostgreSQL ==="

              sudo -u postgres psql \
                -c "ALTER SYSTEM SET listen_addresses = '*';"

              # ------------------------------------------------------------
              # 9. Create PostgreSQL user
              # ------------------------------------------------------------

              echo "=== Creating PostgreSQL user ==="

              sudo -u postgres psql <<SQL
              DO \$\$
              BEGIN
                IF NOT EXISTS (
                  SELECT FROM pg_roles
                  WHERE rolname = 'travel'
                ) THEN
                  CREATE ROLE travel LOGIN PASSWORD '$DB_PASSWORD';
                ELSE
                  ALTER ROLE travel
                  WITH LOGIN PASSWORD '$DB_PASSWORD';
                END IF;
              END
              \$\$;
              SQL

              # ------------------------------------------------------------
              # 10. Create travel database
              # ------------------------------------------------------------

              echo "=== Creating travel database ==="

              sudo -u postgres psql <<'SQL'
              SELECT 'CREATE DATABASE travel OWNER travel'
              WHERE NOT EXISTS (
                SELECT FROM pg_database
                WHERE datname = 'travel'
              )\gexec
              SQL

              # ------------------------------------------------------------
              # 11. Configure pg_hba.conf
              # ------------------------------------------------------------

              echo "=== Configuring pg_hba.conf ==="

              PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -n 1)

              if ! grep -qE \
                '^[[:space:]]*host[[:space:]]+travel[[:space:]]+travel[[:space:]]+10\.0\.1\.0/24' \
                "$PG_HBA"; then

                echo "host    travel    travel    10.0.1.0/24    scram-sha-256" \
                  >> "$PG_HBA"
              fi

              # ------------------------------------------------------------
              # 12. Restart PostgreSQL
              # ------------------------------------------------------------

              echo "=== Restarting PostgreSQL ==="

              systemctl restart postgresql

              # ------------------------------------------------------------
              # 13. Verify PostgreSQL
              # ------------------------------------------------------------

              echo "=== Verifying PostgreSQL ==="

              systemctl is-active --quiet postgresql

              sudo -u postgres psql \
                -c "SELECT version();"

              sudo -u postgres psql \
                -c "\du"

              sudo -u postgres psql \
                -c "\l"

              echo "=== Checking PostgreSQL port ==="

              ss -lntp | grep ':5432'

              echo "=== PostgreSQL bootstrap completed successfully ==="
              EOF

  tags = {
    Name    = "travel-planner-postgres"
    Project = "TravelPlanner"
  }
}

# ------------------------------------------------------------
# Dedicated PostgreSQL EBS volume
# ------------------------------------------------------------

resource "aws_ebs_volume" "postgres_data" {
  availability_zone = aws_instance.postgres.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "travel-planner-postgres-data"
    Project = "TravelPlanner"
  }
}

resource "aws_volume_attachment" "postgres_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.postgres_data.id
  instance_id = aws_instance.postgres.id
}