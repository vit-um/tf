terraform {
  backend "gcs" {
    bucket  = "vit-secret"
    prefix  = "terraform/state"
  }
}


module "github_repository" {
  source                   = "github.com/vit-um/tf-github-repository"
  github_owner             = var.GITHUB_OWNER
  github_token             = var.GITHUB_TOKEN
  repository_name          = var.FLUX_GITHUB_REPO
  public_key_openssh       = module.tls_private_key.public_key_openssh
  public_key_openssh_title = "flux0"
}

# "github.com/vit-um/tf-google-gke-cluster"

module "gke_cluster" {
  source         = "./modules/gke_cluster"
  GOOGLE_REGION  = var.GOOGLE_REGION
  GOOGLE_PROJECT = var.GOOGLE_PROJECT
  GKE_NUM_NODES  = 1
}

module "tls_private_key" {
  source    = "github.com/vit-um/tf-hashicorp-tls-keys"
  algorithm = "RSA"
}

# "github.com/vit-um/tf-fluxcd-flux-bootstrap?ref=gke_auth"

module "flux_bootstrap" {
  source            = "./modules/flux_bootstrap"
  github_repository = "${var.GITHUB_OWNER}/${var.FLUX_GITHUB_REPO}"
  private_key       = module.tls_private_key.private_key_pem
  config_host       = module.gke_cluster.config_host
  config_token      = module.gke_cluster.config_token
  config_ca         = module.gke_cluster.config_ca
  github_token      = var.GITHUB_TOKEN
}

