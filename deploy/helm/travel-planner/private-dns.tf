resource "aws_route53_zone" "travel_planner_private" {
  name = "travel-planner.internal"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  comment = "Private DNS zone for TravelPlanner AWS infrastructure"

  tags = {
    Name    = "travel-planner-private-zone"
    Project = "TravelPlanner"
  }
}

resource "aws_route53_record" "postgres" {
  zone_id = aws_route53_zone.travel_planner_private.zone_id

  name = "postgres.travel-planner.internal"

  type = "A"
  ttl  = 30

  records = [
    aws_instance.postgres.private_ip
  ]
}