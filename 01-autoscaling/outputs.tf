output "alb_dns_name" {
  description = "ALB DNS name — open in browser to see the welcome page"
  value       = aws_lb.main.dns_name
}
