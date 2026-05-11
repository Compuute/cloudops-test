module "vm" {
  source = "../../modules/vm"

  name           = "staging-app"
  env            = "staging"
  instance_count = 1
  server_type    = "cx22"  # 2 vCPU, 4GB RAM
  ssh_public_key = var.ssh_public_key
  storage_size_gb = 40
  prevent_destroy = false
}

module "networking" {
  source = "../../modules/networking"

  name       = "staging"
  domain     = var.domain
  server_ids = module.vm.server_ids
  server_ips = module.vm.server_ips
}

module "storage" {
  source = "../../modules/storage"

  bucket_name    = "mycompany-staging-backups"
  env            = "staging"
  retention_days = 14
}

# generate ansible inventory from terraform outputs
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory/staging/hosts.yml"
  file_permission = "0644"
  content         = templatefile("${path.module}/inventory.tftpl", {
    servers = module.vm.server_ips
    names   = module.vm.server_names
    env     = "staging"
  })
}
