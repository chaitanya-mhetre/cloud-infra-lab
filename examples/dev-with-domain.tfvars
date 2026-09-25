# terraform -chdir=envs/dev apply -var-file=../../examples/dev-with-domain.tfvars
github_owner         = "your-github-username"
domain_name          = "dev.example.com" # A record → the `public_ip` output (create it after the first apply)
acme_email           = "you@example.com"
public_ingress_cidrs = ["203.0.113.10/32"] # your IP only while demoing
alarm_email          = "you@example.com"
