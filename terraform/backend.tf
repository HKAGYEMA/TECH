terraform {
  backend "s3" {
    bucket = "kpmg-bucket-test1"
    key    = "path/to/my/key"
    region = "eu-west-2"
  }
}
