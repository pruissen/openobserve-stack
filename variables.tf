variable "zo_root_email" {
  description = "OpenObserve Root Email"
  type        = string
  default     = "admin@example.com"
}

variable "zo_root_password" {
  description = "OpenObserve Root Password"
  type        = string
  sensitive   = true
  default     = "ComplexPassword123!"
}

variable "minio_root_user" {
  description = "MinIO Root User"
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "MinIO Root Password"
  type        = string
  sensitive   = true
  default     = "MinioPassword123!"
}

variable "org_team" {
  default = "observability_team"
}

variable "org_platform" {
  default = "observability_platform"
}