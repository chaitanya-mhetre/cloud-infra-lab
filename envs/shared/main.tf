# Long-lived, cheap resources shared by every environment.
# Images are built ONCE per commit and promoted dev -> staging -> prod-like by tag,
# so the registry must outlive any single environment.
module "registry" {
  source = "../../modules/registry"

  name         = var.project
  repositories = ["slotwise", "rag-engine"]
}
