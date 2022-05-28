# Output variable: DNS Name of ELB
output "elb_dns_name" {
  value = "${aws_elb.example.dns_name}" 
}
output "elb_status" {
  value = "${aws_elb.example}" 
}