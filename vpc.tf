# =============================================================================
# Networking foundation for the cluster.
#
# Layout (single NAT Gateway design):
#
#   VPC 10.0.0.0/16
#   ├── Internet Gateway
#   ├── Public subnet  AZ-a  10.0.0.0/24   -> holds the NAT Gateway
#   ├── Private subnet AZ-a  10.0.10.0/24  -> control-plane + worker-1
#   ├── Private subnet AZ-b  10.0.11.0/24  -> worker-2
#   ├── Public route table  : 0.0.0.0/0 -> IGW      (public subnet)
#   └── Private route table : 0.0.0.0/0 -> NAT GW   (both private subnets)
#
# Terraform figures out creation order automatically from the references
# between resources (e.g. a subnet references aws_vpc.main.id), so we don't
# declare dependencies by hand -- this is the implicit dependency graph.
# =============================================================================

# ---- VPC --------------------------------------------------------------------
# The private network. enable_dns_* lets instances resolve DNS and get
# internal DNS names, which Kubernetes and the SSM agent both rely on.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name                                        = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ---- Internet Gateway -------------------------------------------------------
# Attaches to the VPC and provides internet reachability for anything whose
# route table points 0.0.0.0/0 at it (our public subnet).
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# ---- Public subnet ----------------------------------------------------------
# Holds ONLY the NAT Gateway (no cluster nodes). It's "public" purely because
# its route table (below) routes to the Internet Gateway.
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zones[0]

  tags = {
    Name                                        = "${var.cluster_name}-public-${var.availability_zones[0]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Tag used by the AWS cloud controller to place internet-facing load
    # balancers (harmless if we never enable cloud integration).
    "kubernetes.io/role/elb" = "1"
  }
}

# ---- Private subnets --------------------------------------------------------
# Two subnets, one per AZ, holding the actual k8s nodes. No public IPs.
# count = 2 creates a small list of subnets; each reads its CIDR/AZ by index.
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                        = "${var.cluster_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Tag used by the AWS cloud controller for internal load balancers.
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ---- Elastic IP for the NAT Gateway -----------------------------------------
# A NAT Gateway needs a static public IP. domain = "vpc" marks it as a VPC EIP.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }

  # The EIP can only be associated once the IGW exists; this makes the
  # ordering explicit even though it's usually inferred.
  depends_on = [aws_internet_gateway.main]
}

# ---- NAT Gateway ------------------------------------------------------------
# Lives in the PUBLIC subnet (must, so its own egress routes to the IGW).
# Gives the private subnets OUTBOUND-only internet: image pulls, packages, SSM.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.cluster_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# ---- Public route table -----------------------------------------------------
# 0.0.0.0/0 -> IGW. Associating the public subnet with this table is what
# actually makes that subnet "public".
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

# ---- Private route table ----------------------------------------------------
# 0.0.0.0/0 -> NAT Gateway. Both private subnets share this one table, so both
# AZs route their egress through the single NAT (the accepted cross-AZ SPOF).
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

# One association per private subnet -> the shared private route table.
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
