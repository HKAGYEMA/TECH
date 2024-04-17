terraform {
  backend "s3" {
    bucket = "tech-bucket-lexnux1"
    key    = "path/to/my/key"
    region = "eu-west-2"
  }
}
