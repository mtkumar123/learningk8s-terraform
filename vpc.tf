# =============================================================================
# Networking foundation for the EKS cluster.
#
# Layout (single NAT Gateway design):
#
#   VPC 10.0.0.0/16
#   ├── Internet Gateway
#   ├── Public subnet  AZ-a  10.0.0.0/24   -> holds the NAT Gateway
#   ├── Private subnet AZ-a  10.0.10.0/24  -> worker nodes
#   ├── Private subnet AZ-b  10.0.11.0/24  -> worker nodes
#   ├── Private subnet AZ-c  10.0.12.0/24  -> worker nodes
#   ├── Public route table  : 0.0.0.0/0 -> IGW     (public subnet)
#   └── Private route table : 0.0.0.0/0 -> NAT GW  (all private subnets)
#
# EKS-specific subnet tags let the cluster auto-discover subnets when creating
# load balancers for Service type=LoadBalancer / Ingress:
#   kubernetes.io/role/elb          = 1  -> public subnets  (internet-facing LBs)
#   kubernetes.io/role/internal-elb = 1  -> private subnets (internal LBs)
# =============================================================================

# ---- VPC --------------------------------------------------------------------
# EKS requires DNS support + hostnames so nodes get internal DNS names and can
# resolve the cluster API endpoint.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# ---- Internet Gateway -------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# ---- Public subnet ----------------------------------------------------------
# Holds the NAT Gateway. Tagged so EKS can place internet-facing load balancers
# here. map_public_ip_on_launch lets the NAT GW (and any future public
# resources) receive a public IP.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.cluster_name}-public-${var.availability_zones[0]}"
    "kubernetes.io/role/elb" = "1"
  }
}

# ---- Second public subnet ---------------------------------------------------
# An internet-facing ALB requires public subnets in at least 2 AZs. This one
# lives in AZ-b. It doesn't hold a NAT (we keep the single-NAT design); it
# exists so the load balancer controller can place a cross-AZ ALB.
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_b
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.cluster_name}-public-${var.availability_zones[1]}"
    "kubernetes.io/role/elb" = "1"
  }
}

# ---- Private subnets --------------------------------------------------------
# One per AZ, holding the worker nodes (no public IPs). Tagged for internal
# load balancers.
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                              = "${var.cluster_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ---- Elastic IP for the NAT Gateway -----------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# ---- NAT Gateway ------------------------------------------------------------
# Lives in the PUBLIC subnet. Gives private-subnet worker nodes OUTBOUND-only
# internet: pulling container images, reaching the EKS API endpoint, ECR, etc.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.cluster_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# ---- Public route table -----------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# The second public subnet shares the same public route table (0.0.0.0/0 -> IGW).
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ---- Private route table ----------------------------------------------------
# All private subnets share one route table -> single NAT (accepted SPOF for a
# learning cluster; production would use one NAT per AZ).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
