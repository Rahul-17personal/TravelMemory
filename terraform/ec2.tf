# ---------- Web server (public subnet) ----------
resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "${var.project_name}-web-server"
  }
}

# ---------- Database server (private subnet) ----------
resource "aws_instance" "db" {
  ami                     = var.ami_id
  instance_type           = var.instance_type
  subnet_id               = aws_subnet.private.id
  vpc_security_group_ids  = [aws_security_group.db.id]
  key_name                = var.key_name
  iam_instance_profile    = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "${var.project_name}-db-server"
  }
}
