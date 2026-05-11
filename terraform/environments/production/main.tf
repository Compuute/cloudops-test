module "vm" {
  source = "../../modules/vm"

  name            = "prod-app"
  env             = "production"
  instance_count  = 2
  server_type     = "cx32"  # 4 vCPU, 8GB RAM
  ssh_public_key  = var.ssh_public_key
  storage_size_gb = 100
  prevent_destroy = true   # terraform destroy will fail without -target override
}

module "networking" {
  source = "../../modules/networking"

  name              = "production"
  domain            = var.domain
  server_ids        = module.vm.server_ids
  server_ips        = module.vm.server_ips
  ssh_allowed_cidrs = var.ssh_allowed_cidrs
}

module "storage" {
  source = "../../modules/storage"

  bucket_name    = "mycompany-prod-backups"
  env            = "production"
  retention_days = 30
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory/production/hosts.yml"
  file_permission = "0644"
  content         = templatefile("${path.module}/inventory.tftpl", {
    servers = module.vm.server_ips
    names   = module.vm.server_names
    env     = "production"
  })
}
