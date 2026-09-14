# ============================================================
# TravelPlanner - WireGuard
# ============================================================

resource "aws_vpc_security_group_ingress_rule" "wireguard_udp" {
  security_group_id = aws_security_group.k3s.id

  description = "TravelPlanner WireGuard VPN"

  cidr_ipv4 = "0.0.0.0/0"

  from_port = 51820
  to_port   = 51820

  ip_protocol = "udp"
}