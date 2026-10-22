config {
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  version = "0.15.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
  preset  = "recommended"
}

rule "terraform_standard_module_structure" {
  enabled = false
}
