output "vpc_id"              { value = aws_vpc.main.id }
output "public_subnet_ids"   { value = [aws_subnet.publicsubnet1.id, aws_subnet.publicsubnet2.id] }
output "private_subnet_ids"  { value = [aws_subnet.privatesubnet1.id, aws_subnet.privatesubnet2.id] }
output "alb_sg_id"           { value = aws_security_group.alb-sg.id }
output "ecs_sg_id"           { value = aws_security_group.ecs-sg.id }
output "rds_sg_id"           { value = aws_security_group.rds_sg.id }
output "cache_sg_id"         { value = aws_security_group.cache-sg.id }
output "kms_key_arn"         { value = aws_kms_key.main.arn }