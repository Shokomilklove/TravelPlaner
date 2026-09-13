resource "aws_iam_role" "ssm" {
  name = "travel-planner-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "travel-planner-ssm-role"
    Project = "TravelPlanner"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "password_parameter" {
  name = "travel-planner-password-parameter"
  role = aws_iam_role.ssm.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]

        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/travel-planner/postgres-password"
      }
    ]
  })
}

resource "aws_iam_role_policy" "route53_read" {
  name = "travel-planner-route53-read"
  role = aws_iam_role.ssm.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ListHostedZones"
        Effect = "Allow"

        Action = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName"
        ]

        Resource = "*"
      },
      {
        Sid    = "ReadHostedZoneRecords"
        Effect = "Allow"

        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets"
        ]

        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ssm" {
  name = "travel-planner-ssm-profile"
  role = aws_iam_role.ssm.name

  tags = {
    Name    = "travel-planner-ssm-profile"
    Project = "TravelPlanner"
  }
}