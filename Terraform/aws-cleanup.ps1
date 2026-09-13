#requires -Version 5.1

<#
.SYNOPSIS
    AWS cleanup script for Windows PowerShell.

.DESCRIPTION
    Finds and optionally deletes common AWS resources left after
    Terraform state was lost.

    IMPORTANT:
    - Does NOT delete IAM users.
    - Does NOT delete the AWS account.
    - Does NOT delete system/service-linked IAM roles.
    - S3 buckets are emptied before deletion.
    - RDS deletion does NOT create a final snapshot.
    - Use -DryRun first.

.EXAMPLES

    # Only show what exists
    .\aws-cleanup.ps1 -DryRun

    # Delete resources after confirmation
    .\aws-cleanup.ps1

    # Only work in selected regions
    .\aws-cleanup.ps1 -Regions @("eu-central-1","us-east-1")
#>

param(
    [switch]$DryRun,

    [string[]]$Regions = @(
        "eu-central-1",
        "eu-west-1",
        "eu-west-2",
        "eu-central-2",
        "us-east-1",
        "us-east-2",
        "us-west-1",
        "us-west-2"
    )
)

$ErrorActionPreference = "Continue"

# ============================================================
# Helpers
# ============================================================

function Write-Section {
    param([string]$Text)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Text)

    Write-Host "[INFO] $Text" -ForegroundColor Gray
}

function Write-OK {
    param([string]$Text)

    Write-Host "[ OK ] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)

    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)

    Write-Host "[ERR ] $Text" -ForegroundColor Red
}

function Invoke-AwsSafe {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments
    )

    try {
        $result = & aws @Arguments 2>&1

        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        return $result
    }
    catch {
        return $null
    }
}

function Confirm-Action {
    param(
        [string]$Message
    )

    $answer = Read-Host "$Message Type YES to continue"

    return ($answer -eq "YES")
}

# ============================================================
# Check AWS CLI
# ============================================================

Write-Section "AWS CLEANUP"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Err "AWS CLI was not found."
    Write-Host ""
    Write-Host "Install AWS CLI first, then run this script again."
    exit 1
}

Write-Info "AWS CLI found."

# ============================================================
# Check credentials
# ============================================================

Write-Section "AWS ACCOUNT"

$identity = Invoke-AwsSafe @(
    "sts",
    "get-caller-identity",
    "--output",
    "json"
)

if (-not $identity) {
    Write-Err "AWS credentials are not working."
    Write-Host ""
    Write-Host "Run:"
    Write-Host "  aws configure"
    Write-Host ""
    Write-Host "or configure your AWS profile."
    exit 1
}

$identityJson = $identity -join "`n"
$identityObj = $identityJson | ConvertFrom-Json

Write-Host "Account : $($identityObj.Account)" -ForegroundColor Yellow
Write-Host "User/ARN: $($identityObj.Arn)" -ForegroundColor Yellow

Write-Host ""

if (-not (Confirm-Action "Is this the AWS account you want to clean?")) {
    Write-Warn "Cancelled."
    exit 0
}

# ============================================================
# INVENTORY
# ============================================================

$Inventory = @()

Write-Section "INVENTORY"

foreach ($Region in $Regions) {

    Write-Host ""
    Write-Host "REGION: $Region" -ForegroundColor Magenta

    # --------------------------------------------------------
    # EC2
    # --------------------------------------------------------

    $instances = Invoke-AwsSafe @(
        "ec2",
        "describe-instances",
        "--region",
        $Region,
        "--query",
        "Reservations[].Instances[?State.Name!='terminated'].[InstanceId,State.Name,InstanceType,PrivateIpAddress,PublicIpAddress]",
        "--output",
        "json"
    )

    if ($instances) {
        try {
            $items = ($instances -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "EC2"
                    Id     = $item[0]
                    Extra  = "$($item[1]) $($item[2])"
                }

                Write-Host "  EC2: $($item[0]) [$($item[1])]" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # EBS
    # --------------------------------------------------------

    $volumes = Invoke-AwsSafe @(
        "ec2",
        "describe-volumes",
        "--region",
        $Region,
        "--query",
        "Volumes[].[VolumeId,State,Size]",
        "--output",
        "json"
    )

    if ($volumes) {
        try {
            $items = ($volumes -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "EBS"
                    Id     = $item[0]
                    Extra  = "$($item[1]) $($item[2])GB"
                }

                Write-Host "  EBS: $($item[0]) [$($item[1]) $($item[2])GB]" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # Elastic IP
    # --------------------------------------------------------

    $eips = Invoke-AwsSafe @(
        "ec2",
        "describe-addresses",
        "--region",
        $Region,
        "--query",
        "Addresses[].[AllocationId,PublicIp,AssociationId]",
        "--output",
        "json"
    )

    if ($eips) {
        try {
            $items = ($eips -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "ElasticIP"
                    Id     = $item[0]
                    Extra  = "$($item[1])"
                }

                Write-Host "  EIP: $($item[0]) [$($item[1])]" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # NAT Gateways
    # --------------------------------------------------------

    $nats = Invoke-AwsSafe @(
        "ec2",
        "describe-nat-gateways",
        "--region",
        $Region,
        "--filter",
        "Name=state,Values=available,pending,deleting",
        "--query",
        "NatGateways[].[NatGatewayId,State,VpcId]",
        "--output",
        "json"
    )

    if ($nats) {
        try {
            $items = ($nats -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "NAT"
                    Id     = $item[0]
                    Extra  = "$($item[1]) VPC=$($item[2])"
                }

                Write-Host "  NAT: $($item[0]) [$($item[1])]" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # Load Balancers
    # --------------------------------------------------------

    $lbs = Invoke-AwsSafe @(
        "elbv2",
        "describe-load-balancers",
        "--region",
        $Region,
        "--query",
        "LoadBalancers[].[LoadBalancerArn,LoadBalancerName,Type,State.Code]",
        "--output",
        "json"
    )

    if ($lbs) {
        try {
            $items = ($lbs -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "ALB/NLB"
                    Id     = $item[0]
                    Extra  = "$($item[1]) $($item[2])"
                }

                Write-Host "  LB: $($item[1]) [$($item[2])]" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # Target Groups
    # --------------------------------------------------------

    $targets = Invoke-AwsSafe @(
        "elbv2",
        "describe-target-groups",
        "--region",
        $Region,
        "--query",
        "TargetGroups[].[TargetGroupArn,TargetGroupName]",
        "--output",
        "json"
    )

    if ($targets) {
        try {
            $items = ($targets -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "TargetGroup"
                    Id     = $item[0]
                    Extra  = "$($item[1])"
                }

                Write-Host "  TG: $($item[1])" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # RDS
    # --------------------------------------------------------

    $rds = Invoke-AwsSafe @(
        "rds",
        "describe-db-instances",
        "--region",
        $Region,
        "--query",
        "DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Engine]",
        "--output",
        "json"
    )

    if ($rds) {
        try {
            $items = ($rds -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "RDS"
                    Id     = $item[0]
                    Extra  = "$($item[1]) $($item[2])"
                }

                Write-Host "  RDS: $($item[0]) [$($item[1])]" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # ECR
    # --------------------------------------------------------

    $ecr = Invoke-AwsSafe @(
        "ecr",
        "describe-repositories",
        "--region",
        $Region,
        "--query",
        "repositories[].[repositoryName,repositoryUri]",
        "--output",
        "json"
    )

    if ($ecr) {
        try {
            $items = ($ecr -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {
                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "ECR"
                    Id     = $item[0]
                    Extra  = "$($item[1])"
                }

                Write-Host "  ECR: $($item[0])" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # CloudWatch Log Groups
    # --------------------------------------------------------

    $logs = Invoke-AwsSafe @(
        "logs",
        "describe-log-groups",
        "--region",
        $Region,
        "--query",
        "logGroups[].logGroupName",
        "--output",
        "json"
    )

    if ($logs) {
        try {
            $items = ($logs -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {

                # Only list common application/project logs.
                if (
                    $item -like "*travel*" -or
                    $item -like "*trip*" -or
                    $item -like "*jenkins*" -or
                    $item -like "*k3s*" -or
                    $item -like "*ec2*" -or
                    $item -like "/aws/*"
                ) {
                    $Inventory += [PSCustomObject]@{
                        Region = $Region
                        Type   = "CloudWatchLog"
                        Id     = $item
                        Extra  = ""
                    }

                    Write-Host "  LOG: $item" -ForegroundColor Yellow
                }
            }
        }
        catch {}
    }

    # --------------------------------------------------------
    # VPCs
    # --------------------------------------------------------

    $vpcs = Invoke-AwsSafe @(
        "ec2",
        "describe-vpcs",
        "--region",
        $Region,
        "--query",
        "Vpcs[].[VpcId,IsDefault,CidrBlock]",
        "--output",
        "json"
    )

    if ($vpcs) {
        try {
            $items = ($vpcs -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {

                $vpcId = $item[0]
                $isDefault = $item[1]

                if ($isDefault -eq $true) {
                    Write-Host "  VPC: $vpcId [DEFAULT - WILL NOT DELETE]" -ForegroundColor DarkYellow
                }
                else {
                    $Inventory += [PSCustomObject]@{
                        Region = $Region
                        Type   = "VPC"
                        Id     = $vpcId
                        Extra  = "$($item[2])"
                    }

                    Write-Host "  VPC: $vpcId [$($item[2])]" -ForegroundColor Yellow
                }
            }
        }
        catch {}
    }
}

# ============================================================
# GLOBAL S3 INVENTORY
# ============================================================

Write-Section "S3"

$buckets = Invoke-AwsSafe @(
    "s3api",
    "list-buckets",
    "--query",
    "Buckets[].Name",
    "--output",
    "json"
)

if ($buckets) {
    try {
        $bucketItems = ($buckets -join "`n") | ConvertFrom-Json

        foreach ($bucket in $bucketItems) {

            $Inventory += [PSCustomObject]@{
                Region = "GLOBAL"
                Type   = "S3"
                Id     = $bucket
                Extra  = ""
            }

            Write-Host "  S3: $bucket" -ForegroundColor Yellow
        }
    }
    catch {}
}

# ============================================================
# CloudFormation
# ============================================================

Write-Section "CLOUDFORMATION"

foreach ($Region in $Regions) {

    $stacks = Invoke-AwsSafe @(
        "cloudformation",
        "list-stacks",
        "--region",
        $Region,
        "--stack-status-filter",
        "CREATE_COMPLETE",
        "UPDATE_COMPLETE",
        "UPDATE_ROLLBACK_COMPLETE",
        "IMPORT_COMPLETE",
        "ROLLBACK_COMPLETE",
        "--query",
        "StackSummaries[].[StackName,StackStatus]",
        "--output",
        "json"
    )

    if ($stacks) {
        try {
            $items = ($stacks -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {

                $Inventory += [PSCustomObject]@{
                    Region = $Region
                    Type   = "CloudFormation"
                    Id     = $item[0]
                    Extra  = $item[1]
                }

                Write-Host "  STACK: $($item[0]) [$($item[1])]" -ForegroundColor Yellow
            }
        }
        catch {}
    }
}

# ============================================================
# SUMMARY
# ============================================================

Write-Section "SUMMARY"

if ($Inventory.Count -eq 0) {

    Write-OK "No resources from the cleanup categories were found."

}
else {

    $Inventory |
        Sort-Object Region, Type, Id |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Total resources found: $($Inventory.Count)" -ForegroundColor Yellow
}

# ============================================================
# DRY RUN
# ============================================================

if ($DryRun) {

    Write-Section "DRY RUN"

    Write-Host "Nothing was deleted." -ForegroundColor Green
    Write-Host ""
    Write-Host "To actually delete the resources run:"
    Write-Host ""
    Write-Host "  .\aws-cleanup.ps1" -ForegroundColor Yellow
    Write-Host ""

    exit 0
}

# ============================================================
# FINAL CONFIRMATION
# ============================================================

Write-Section "DELETION WARNING"

Write-Host "WARNING!" -ForegroundColor Red
Write-Host ""
Write-Host "The next step will permanently delete AWS resources."
Write-Host ""
Write-Host "The script will NOT delete:"
Write-Host "  - AWS account"
Write-Host "  - root user"
Write-Host "  - IAM users"
Write-Host "  - system/service-linked IAM roles"
Write-Host "  - DEFAULT VPCs"
Write-Host ""
Write-Host "The script WILL attempt to delete:"
Write-Host "  - EC2 instances"
Write-Host "  - EBS volumes"
Write-Host "  - Elastic IPs"
Write-Host "  - NAT gateways"
Write-Host "  - Load balancers"
Write-Host "  - Target groups"
Write-Host "  - RDS instances"
Write-Host "  - ECR repositories"
Write-Host "  - selected CloudWatch logs"
Write-Host "  - non-default VPCs"
Write-Host "  - S3 buckets"
Write-Host "  - selected CloudFormation stacks"
Write-Host ""

if (-not (Confirm-Action "START DELETION?")) {

    Write-Warn "Deletion cancelled."
    exit 0
}

# ============================================================
# DELETE
# ============================================================

Write-Section "DELETING RESOURCES"

# ------------------------------------------------------------
# 1. Auto Scaling Groups
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    Write-Info "Checking Auto Scaling Groups in $Region..."

    $groups = Invoke-AwsSafe @(
        "autoscaling",
        "describe-auto-scaling-groups",
        "--region",
        $Region,
        "--query",
        "AutoScalingGroups[].AutoScalingGroupName",
        "--output",
        "json"
    )

    if ($groups) {
        try {
            $items = ($groups -join "`n") | ConvertFrom-Json

            foreach ($group in $items) {

                Write-Host "Deleting ASG: $group" -ForegroundColor Yellow

                & aws autoscaling update-auto-scaling-group `
                    --auto-scaling-group-name $group `
                    --region $Region `
                    --min-size 0 `
                    --max-size 0 `
                    --desired-capacity 0 2>$null

                & aws autoscaling delete-auto-scaling-group `
                    --auto-scaling-group-name $group `
                    --region $Region `
                    --force-delete 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 2. EC2 Instances
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $instances = Invoke-AwsSafe @(
        "ec2",
        "describe-instances",
        "--region",
        $Region,
        "--query",
        "Reservations[].Instances[?State.Name!='terminated'].InstanceId",
        "--output",
        "json"
    )

    if ($instances) {
        try {
            $items = ($instances -join "`n") | ConvertFrom-Json

            if ($items) {

                foreach ($id in $items) {

                    Write-Host "Terminating EC2: $id [$Region]" -ForegroundColor Yellow

                    & aws ec2 terminate-instances `
                        --instance-ids $id `
                        --region $Region 2>$null
                }
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 3. Wait for EC2 termination
# ------------------------------------------------------------

Write-Info "Waiting for EC2 termination..."

Start-Sleep -Seconds 10

# ------------------------------------------------------------
# 4. Load Balancers
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $lbs = Invoke-AwsSafe @(
        "elbv2",
        "describe-load-balancers",
        "--region",
        $Region,
        "--query",
        "LoadBalancers[].LoadBalancerArn",
        "--output",
        "json"
    )

    if ($lbs) {
        try {
            $items = ($lbs -join "`n") | ConvertFrom-Json

            foreach ($arn in $items) {

                Write-Host "Deleting Load Balancer: $arn" -ForegroundColor Yellow

                & aws elbv2 delete-load-balancer `
                    --load-balancer-arn $arn `
                    --region $Region 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 5. Target Groups
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $targets = Invoke-AwsSafe @(
        "elbv2",
        "describe-target-groups",
        "--region",
        $Region,
        "--query",
        "TargetGroups[].TargetGroupArn",
        "--output",
        "json"
    )

    if ($targets) {
        try {
            $items = ($targets -join "`n") | ConvertFrom-Json

            foreach ($arn in $items) {

                Write-Host "Deleting Target Group: $arn" -ForegroundColor Yellow

                & aws elbv2 delete-target-group `
                    --target-group-arn $arn `
                    --region $Region 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 6. NAT Gateways
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $nats = Invoke-AwsSafe @(
        "ec2",
        "describe-nat-gateways",
        "--region",
        $Region,
        "--filter",
        "Name=state,Values=available,pending",
        "--query",
        "NatGateways[].NatGatewayId",
        "--output",
        "json"
    )

    if ($nats) {
        try {
            $items = ($nats -join "`n") | ConvertFrom-Json

            foreach ($nat in $items) {

                Write-Host "Deleting NAT Gateway: $nat [$Region]" -ForegroundColor Yellow

                & aws ec2 delete-nat-gateway `
                    --nat-gateway-id $nat `
                    --region $Region 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 7. RDS
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $rds = Invoke-AwsSafe @(
        "rds",
        "describe-db-instances",
        "--region",
        $Region,
        "--query",
        "DBInstances[].DBInstanceIdentifier",
        "--output",
        "json"
    )

    if ($rds) {
        try {
            $items = ($rds -join "`n") | ConvertFrom-Json

            foreach ($db in $items) {

                Write-Host "Deleting RDS: $db [$Region]" -ForegroundColor Yellow

                & aws rds delete-db-instance `
                    --db-instance-identifier $db `
                    --region $Region `
                    --skip-final-snapshot `
                    --delete-automated-backups 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 8. ECR
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $ecr = Invoke-AwsSafe @(
        "ecr",
        "describe-repositories",
        "--region",
        $Region,
        "--query",
        "repositories[].repositoryName",
        "--output",
        "json"
    )

    if ($ecr) {
        try {
            $items = ($ecr -join "`n") | ConvertFrom-Json

            foreach ($repo in $items) {

                Write-Host "Deleting ECR: $repo [$Region]" -ForegroundColor Yellow

                & aws ecr delete-repository `
                    --repository-name $repo `
                    --region $Region `
                    --force 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 9. CloudWatch Logs
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $logs = Invoke-AwsSafe @(
        "logs",
        "describe-log-groups",
        "--region",
        $Region,
        "--query",
        "logGroups[].logGroupName",
        "--output",
        "json"
    )

    if ($logs) {
        try {
            $items = ($logs -join "`n") | ConvertFrom-Json

            foreach ($log in $items) {

                if (
                    $log -like "*travel*" -or
                    $log -like "*trip*" -or
                    $log -like "*jenkins*" -or
                    $log -like "*k3s*" -or
                    $log -like "*ec2*" -or
                    $log -like "/aws/*"
                ) {

                    Write-Host "Deleting CloudWatch Log Group: $log [$Region]" -ForegroundColor Yellow

                    & aws logs delete-log-group `
                        --log-group-name $log `
                        --region $Region 2>$null
                }
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 10. EBS Volumes
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $volumes = Invoke-AwsSafe @(
        "ec2",
        "describe-volumes",
        "--region",
        $Region,
        "--filter",
        "Name=status,Values=available",
        "--query",
        "Volumes[].VolumeId",
        "--output",
        "json"
    )

    if ($volumes) {
        try {
            $items = ($volumes -join "`n") | ConvertFrom-Json

            foreach ($volume in $items) {

                Write-Host "Deleting EBS: $volume [$Region]" -ForegroundColor Yellow

                & aws ec2 delete-volume `
                    --volume-id $volume `
                    --region $Region 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 11. Elastic IPs
# ------------------------------------------------------------

foreach ($Region in $Regions) {

    $eips = Invoke-AwsSafe @(
        "ec2",
        "describe-addresses",
        "--region",
        $Region,
        "--query",
        "Addresses[].[AllocationId,AssociationId]",
        "--output",
        "json"
    )

    if ($eips) {
        try {
            $items = ($eips -join "`n") | ConvertFrom-Json

            foreach ($item in $items) {

                $allocation = $item[0]
                $association = $item[1]

                if ($association) {

                    Write-Host "Releasing association: $association" -ForegroundColor Yellow

                    & aws ec2 disassociate-address `
                        --association-id $association `
                        --region $Region 2>$null
                }

                Write-Host "Releasing Elastic IP: $allocation [$Region]" -ForegroundColor Yellow

                & aws ec2 release-address `
                    --allocation-id $allocation `
                    --region $Region 2>$null
            }
        }
        catch {}
    }
}

# ------------------------------------------------------------
# 12. S3
# ------------------------------------------------------------

Write-Section "S3 CLEANUP"

$buckets = Invoke-AwsSafe @(
    "s3api",
    "list-buckets",
    "--query",
    "Buckets[].Name",
    "--output",
    "json"
)

if ($buckets) {
    try {
        $items = ($buckets -join "`n") | ConvertFrom-Json

        foreach ($bucket in $items) {

            Write-Host ""
            Write-Host "S3 bucket: $bucket" -ForegroundColor Yellow

            # Remove object versions / delete markers
            & aws s3api list-object-versions `
                --bucket $bucket `
                --query "Versions[].{Key:Key,VersionId:VersionId}" `
                --output json 2>$null |
                Out-File "$env:TEMP\s3versions.json"

            if (Test-Path "$env:TEMP\s3versions.json") {

                try {

                    $versions = Get-Content "$env:TEMP\s3versions.json" -Raw |
                        ConvertFrom-Json

                    if ($versions) {

                        foreach ($v in $versions) {

                            if ($v.Key -and $v.VersionId) {

                                & aws s3api delete-object `
                                    --bucket $bucket `
                                    --key $v.Key `
                                    --version-id $v.VersionId 2>$null
                            }
                        }
                    }
                }
                catch {}
            }

            # Simple objects
            & aws s3 rm "s3://$bucket" --recursive 2>$null

            # Try bucket deletion
            Write-Host "Deleting S3 bucket: $bucket" -ForegroundColor Yellow

            & aws s3api delete-bucket `
                --bucket $bucket 2>$null
        }
    }
    catch {}
}

# ============================================================
# 13. CloudFormation
# ============================================================

foreach ($Region in $Regions) {

    $stacks = Invoke-AwsSafe @(
        "cloudformation",
        "list-stacks",
        "--region",
        $Region,
        "--stack-status-filter",
        "CREATE_COMPLETE",
        "UPDATE_COMPLETE",
        "UPDATE_ROLLBACK_COMPLETE",
        "IMPORT_COMPLETE",
        "ROLLBACK_COMPLETE",
        "--query",
        "StackSummaries[].StackName",
        "--output",
        "json"
    )

    if ($stacks) {
        try {
            $items = ($stacks -join "`n") | ConvertFrom-Json

            foreach ($stack in $items) {

                Write-Host "Deleting CloudFormation stack: $stack [$Region]" -ForegroundColor Yellow

                & aws cloudformation delete-stack `
                    --stack-name $stack `
                    --region $Region 2>$null
            }
        }
        catch {}
    }
}

# ============================================================
# 14. VPC CLEANUP
# ============================================================

Write-Section "VPC CLEANUP"

foreach ($Region in $Regions) {

    Write-Info "Cleaning non-default VPCs in $Region..."

    $vpcs = Invoke-AwsSafe @(
        "ec2",
        "describe-vpcs",
        "--region",
        $Region,
        "--query",
        "Vpcs[?IsDefault==\`false\`].VpcId",
        "--output",
        "json"
    )

    if (-not $vpcs) {
        continue
    }

    try {
        $vpcItems = ($vpcs -join "`n") | ConvertFrom-Json

        foreach ($vpc in $vpcItems) {

            Write-Host ""
            Write-Host "VPC: $vpc" -ForegroundColor Magenta

            # ------------------------------------------------
            # VPC Endpoints
            # ------------------------------------------------

            $endpoints = Invoke-AwsSafe @(
                "ec2",
                "describe-vpc-endpoints",
                "--region",
                $Region,
                "--filters",
                "Name=vpc-id,Values=$vpc",
                "--query",
                "VpcEndpoints[].VpcEndpointId",
                "--output",
                "json"
            )

            if ($endpoints) {

                try {
                    $endpointItems = ($endpoints -join "`n") | ConvertFrom-Json

                    foreach ($endpoint in $endpointItems) {

                        Write-Host "Deleting VPC endpoint: $endpoint" -ForegroundColor Yellow

                        & aws ec2 delete-vpc-endpoints `
                            --vpc-endpoint-ids $endpoint `
                            --region $Region 2>$null
                    }
                }
                catch {}
            }

            # ------------------------------------------------
            # Internet Gateway
            # ------------------------------------------------

            $igws = Invoke-AwsSafe @(
                "ec2",
                "describe-internet-gateways",
                "--region",
                $Region,
                "--filters",
                "Name=attachment.vpc-id,Values=$vpc",
                "--query",
                "InternetGateways[].InternetGatewayId",
                "--output",
                "json"
            )

            if ($igws) {

                try {
                    $igwItems = ($igws -join "`n") | ConvertFrom-Json

                    foreach ($igw in $igwItems) {

                        Write-Host "Detaching IGW: $igw" -ForegroundColor Yellow

                        & aws ec2 detach-internet-gateway `
                            --internet-gateway-id $igw `
                            --vpc-id $vpc `
                            --region $Region 2>$null

                        Write-Host "Deleting IGW: $igw" -ForegroundColor Yellow

                        & aws ec2 delete-internet-gateway `
                            --internet-gateway-id $igw `
                            --region $Region 2>$null
                    }
                }
                catch {}
            }

            # ------------------------------------------------
            # Subnets
            # ------------------------------------------------

            $subnets = Invoke-AwsSafe @(
                "ec2",
                "describe-subnets",
                "--region",
                $Region,
                "--filters",
                "Name=vpc-id,Values=$vpc",
                "--query",
                "Subnets[].SubnetId",
                "--output",
                "json"
            )

            if ($subnets) {

                try {
                    $subnetItems = ($subnets -join "`n") | ConvertFrom-Json

                    foreach ($subnet in $subnetItems) {

                        Write-Host "Deleting subnet: $subnet" -ForegroundColor Yellow

                        & aws ec2 delete-subnet `
                            --subnet-id $subnet `
                            --region $Region 2>$null
                    }
                }
                catch {}
            }

            # ------------------------------------------------
            # Route tables
            # ------------------------------------------------

            $routes = Invoke-AwsSafe @(
                "ec2",
                "describe-route-tables",
                "--region",
                $Region,
                "--filters",
                "Name=vpc-id,Values=$vpc",
                "--query",
                "RouteTables[].RouteTableId",
                "--output",
                "json"
            )

            if ($routes) {

                try {
                    $routeItems = ($routes -join "`n") | ConvertFrom-Json

                    foreach ($route in $routeItems) {

                        # Main route tables cannot be deleted.
                        $mainCheck = Invoke-AwsSafe @(
                            "ec2",
                            "describe-route-tables",
                            "--route-table-ids",
                            $route,
                            "--region",
                            $Region,
                            "--query",
                            "RouteTables[0].Associations[?Main==\`true\`].Main",
                            "--output",
                            "text"
                        )

                        if ($mainCheck -eq "True") {
                            continue
                        }

                        Write-Host "Deleting route table: $route" -ForegroundColor Yellow

                        & aws ec2 delete-route-table `
                            --route-table-id $route `
                            --region $Region 2>$null
                    }
                }
                catch {}
            }

            # ------------------------------------------------
            # Network ACLs
            # ------------------------------------------------

            $acls = Invoke-AwsSafe @(
                "ec2",
                "describe-network-acls",
                "--region",
                $Region,
                "--filters",
                "Name=vpc-id,Values=$vpc",
                "--query",
                "NetworkAcls[?IsDefault==\`false\`].NetworkAclId",
                "--output",
                "json"
            )

            if ($acls) {

                try {
                    $aclItems = ($acls -join "`n") | ConvertFrom-Json

                    foreach ($acl in $aclItems) {

                        Write-Host "Deleting network ACL: $acl" -ForegroundColor Yellow

                        & aws ec2 delete-network-acl `
                            --network-acl-id $acl `
                            --region $Region 2>$null
                    }
                }
                catch {}
            }

            # ------------------------------------------------
            # Security Groups
            # ------------------------------------------------

            $sgs = Invoke-AwsSafe @(
                "ec2",
                "describe-security-groups",
                "--region",
                $Region,
                "--filters",
                "Name=vpc-id,Values=$vpc",
                "--query",
                "SecurityGroups[?GroupName!='default'].GroupId",
                "--output",
                "json"
            )

            if ($sgs) {

                try {
                    $sgItems = ($sgs -join "`n") | ConvertFrom-Json

                    foreach ($sg in $sgItems) {

                        Write-Host "Deleting security group: $sg" -ForegroundColor Yellow

                        & aws ec2 delete-security-group `
                            --group-id $sg `
                            --region $Region 2>$null
                    }
                }
                catch {}
            }

            # ------------------------------------------------
            # Delete VPC
            # ------------------------------------------------

            Write-Host "Deleting VPC: $vpc" -ForegroundColor Yellow

            & aws ec2 delete-vpc `
                --vpc-id $vpc `
                --region $Region 2>$null
        }
    }
    catch {}
}

# ============================================================
# FINAL CHECK
# ============================================================

Write-Section "CLEANUP FINISHED"

Write-Host ""
Write-Host "The deletion commands have been submitted." -ForegroundColor Green
Write-Host ""
Write-Host "AWS resources can take several minutes to disappear."
Write-Host ""
Write-Host "Recommended next step:"
Write-Host ""
Write-Host "  .\aws-cleanup.ps1 -DryRun" -ForegroundColor Yellow
Write-Host ""
Write-Host "Run it again to check what remains."
Write-Host ""

Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "Check AWS Billing / Cost Explorer for remaining charges."
Write-Host "Some resources such as RDS, NAT Gateway and EBS may take time"
Write-Host "to finish deleting."
