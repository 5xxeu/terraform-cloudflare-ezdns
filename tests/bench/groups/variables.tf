variable "hosts" {
  description = "Number of names in records and in every group"
  type        = number
  default     = 1000
}

variable "groups" {
  description = "Number of record groups"
  type        = number
  default     = 10
}
