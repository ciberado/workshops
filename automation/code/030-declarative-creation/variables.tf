variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  type        = string
  description = "Unique prefix used for configuring resource names."
}

variable "port" {
  type        = number
  description = "Port number of the application."
}