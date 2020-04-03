resource "aws_s3_bucket" "s3_website" {
  bucket = "${local.project_name}-${terraform.workspace}-website-11"
  acl    = "private"
  force_destroy = "true"
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
  versioning {
    enabled = var.versioning
  }  
  tags = merge({"Owner" = "devops-deleteme"}, local.tags)
}
resource "aws_s3_bucket_public_access_block" "bucket_access" {
  bucket = aws_s3_bucket.s3_website.id
  block_public_acls   = var.block_public_acls
  block_public_policy = var.block_public_policy
  ignore_public_acls = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "${local.project_name}-${terraform.workspace}-cdn"
}
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.s3_website.id
  depends_on = [aws_cloudfront_origin_access_identity.origin_access_identity]
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"
      },
      "Action": [ "s3:GetObject" ],
      "Resource": [
        "${aws_s3_bucket.s3_website.arn}/*"
      ]
    }
  ]
}
EOF
}
locals {
  s3_origin_id = "S3-${aws_s3_bucket.s3_website.id}"
  domain_name = "sandbox.synergi.barco.com"
  website = "test23"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.s3_website.bucket_domain_name
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "cdn for seed-global which access s3"
  default_root_object = "index.html"

  # logging_config {
  #   include_cookies = false
  #   bucket          = "mylogs.s3.amazonaws.com"
  #   prefix          = "myprefix"
  # }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }


  # price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      #locations        = ["US", "CA", "GB", "DE"]
    }
  }
  tags = {
    Environment = "production"
  }
  aliases = ["${local.website}.${local.domain_name}"]

  viewer_certificate {
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
    acm_certificate_arn = "arn:aws:acm:us-east-1:445275861539:certificate/5404e435-65d8-44bb-835c-61a9f424d9c0"
    
    # cloudfront_default_certificate = true
    # minimum_protocol_version = "TLSv1.1_2016"
  }
}
resource "aws_route53_record" "route53" {
  zone_id = "Z1VYFFAP5901RU"
  name    = local.website
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = "false"
  }
}