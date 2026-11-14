variable "zone_id" {
  description = "Cloudflare Zone ID of the test zone"
  type        = string
}

variable "zone_name" {
  description = "Domain name of the test zone"
  type        = string
}

variable "prefix" {
  description = "Label of this run"
  type        = string
}


variable "alias_attribute" {
  description = "Attribute of the name of an ALIASES record: content before 3.0, name since"
  type        = string
  default     = "name"
}
