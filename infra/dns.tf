
resource "ovh_domain_zone_record" "main-1" {
  zone     = "gaultier.dev"
  fieldtype = "A"
  subdomain = "@"
  target    = "185.199.108.153"
  ttl       = 3600
}


resource "ovh_domain_zone_record" "main-2" {
  zone     = "gaultier.dev"
  fieldtype = "A"
  subdomain = "@"
  target    = "185.199.109.153"
  ttl       = 3600
}


resource "ovh_domain_zone_record" "main-3" {
  zone     = "gaultier.dev"
  fieldtype = "A"
  subdomain = "@"
  target    = "185.199.110.153"
  ttl       = 3600
}


resource "ovh_domain_zone_record" "main-4" {
  zone     = "gaultier.dev"
  fieldtype = "A"
  subdomain = "@"
  target    = "185.199.111.153"
  ttl       = 3600
}

