# Configure the GCP provider
provider "google" {
  project     = "akiva-sandbox"
  region      = "us-central1" 
}

data "google_compute_network" "default" {
  name = "default"
  project     = "akiva-sandbox"
}

# Create a Compute Engine instance template
resource "google_compute_instance_template" "app_instance_template" {
  name         = "app-instance-template"
  machine_type = "e2-micro"  

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-focal-v20220712"
    auto_delete       = true
    boot              = true
  }

  network_interface {
    network = "default"
    access_config {
    }
  }
  service_account {
    email = "653089912503-compute@developer.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }
  tags = ["http-server","https-server","web"]
  metadata_startup_script = file("startup-script.sh")  
}

# Create a managed instance group
resource "google_compute_instance_group_manager" "app_instance_group_manager" {
  name        = "app-instance-group-manager"
  base_instance_name = "app-instance"
  zone               = "us-central1-a"
  version {
    instance_template  = google_compute_instance_template.app_instance_template.self_link_unique
  }
  target_size       = 2  # Change to your desired number of instances
  named_port {
    name = "http"
    port = 8080
  }
}

# Create a firewall rule to allow incoming traffic on ports 80 and 8080
resource "google_compute_firewall" "allow-http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80","8080"]
  }

  source_ranges = ["0.0.0.0/0"]  # Allow traffic from any source (insecure, consider restricting to specific IP ranges)
}

resource "google_compute_global_address" "private_ip_address" {
  provider = google-beta
  project  = "akiva-sandbox"
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = data.google_compute_network.default.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider = google-beta

  network                 = data.google_compute_network.default.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "instance" {
  provider = google-beta
  project = "akiva-sandbox"
  name             = "private-instance-${random_id.db_name_suffix.hex}"
  region           = "us-central1"
  database_version = "POSTGRES_13"

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.default.id
      enable_private_path_for_google_cloud_services = true
    }
  }
}

#Create a Cloud SQL database (PostgreSQL)
resource "google_sql_database" "app_database" {
  name     = "app-database"
  instance = google_sql_database_instance.instance.name
}

# Create a Cloud SQL user (PostgreSQL)
resource "google_sql_user" "app_db_user" {
  name     = "app-db-user"
  instance = google_sql_database_instance.instance.name
  password = "pass"  # Change to a secure password
}


# Create a backend service
resource "google_compute_backend_service" "app_backend_service" {
  name        = "app-backend-service"
  project     = "akiva-sandbox"
  port_name   = join("", [for np in google_compute_instance_group_manager.app_instance_group_manager.named_port : np.name])
  timeout_sec = 30

  backend {
    group = google_compute_instance_group_manager.app_instance_group_manager.instance_group
  }

  health_checks = [google_compute_health_check.app_health_check.self_link]
}

# Create a health check
resource "google_compute_health_check" "app_health_check" {
  name               = "app-health-check"
  check_interval_sec = 5
  timeout_sec        = 5
  unhealthy_threshold = 2
  healthy_threshold   = 2

  http_health_check {
    port        = 8080
    request_path = "/"
  }
}

# Create a URL map
resource "google_compute_url_map" "app_url_map" {
  name            = "app-url-map"
  default_service = google_compute_backend_service.app_backend_service.self_link
}

# Create a target HTTP proxy
resource "google_compute_target_http_proxy" "app_target_http_proxy" {
  name    = "app-target-http-proxy"
  url_map = google_compute_url_map.app_url_map.self_link
}

# Create a global static IP address
resource "google_compute_global_address" "app_global_ip" {
  project = "akiva-sandbox"
  name    = "app-global-ip"
}

# Create a global forwarding rule
resource "google_compute_global_forwarding_rule" "app_global_forwarding_rule" {
  name                  = "app-global-forwarding-rule"
  project               = "akiva-sandbox"
  ip_address            = google_compute_global_address.app_global_ip.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.app_target_http_proxy.self_link
  load_balancing_scheme = "EXTERNAL"
}
