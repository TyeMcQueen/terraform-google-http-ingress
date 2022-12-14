
locals {
  # Parse var.dns-zone-ref to get a project ID and a managed zone title:
  dns-parts = split( "/", var.dns-zone-ref )
  zone-proj = ( 2 == length(local.dns-parts)
    ? local.dns-parts[0] : local.project )

  # Only use local.dns-data-title in 'data "google_dns_managed_zone"' block:
  dns-data-title = ( var.dns-zone-ref == "" ? ""
    : 2 == length(local.dns-parts) ? local.dns-parts[1]
    : 1 == length(local.dns-parts) ? local.dns-parts[0]
    : "ERROR For dns-zone-ref, .id is not supported (${var.dns-zone-ref})" )
}

# Look up managed DNS zone created elsewhere:
data "google_dns_managed_zone" "z" {
  count     = var.dns-zone-ref == "" ? 0 : 1
  name      = local.dns-data-title
  project   = local.zone-proj
}

locals {
  # Version of managed zone title that gives hint if no such zone found:
  zone-title = ( var.dns-zone-ref == "" ? ""
    : [ for name in [ data.google_dns_managed_zone.z[0].name ] :
        try( 0 < length(name), false ) ? name
        : "ERROR DNS Zone ${local.zone-proj}/${local.dns-data-title} not found"
      ][0] )
  zone-domain = ( var.dns-zone-ref == "" ? "/ERROR-no-zone-ref"
    : [ for dom in [ data.google_dns_managed_zone.z[0].dns_name ] :
          try( 0 < length(dom), false )
            ? trimsuffix( dom, "." )
            : "/ERROR-invalid-zone-ref" ][0] )

  keys = [ for e in var.hostnames : split("|",e)[0] ]

  # Build map from hostname to "|" suffix:
  tosuff = { for e in var.hostnames :
    split("|",e)[0] => trimprefix( e, split("|",e)[0] ) }

  # Build map from hostname to fully-qualified hostname:
  tofq = { for h, suff in local.tosuff : h => (
    1 == length(split(".",h))
      ? "${h}.${local.zone-domain}"
      : "." == substr(h,-1,1) ? "${h}${local.zone-domain}" : h )
    if "" != h }

  # Hosts that DNS `A` records can be added for:
  dnshosts = [ for h, fq in local.tofq : fq
    if h != fq && "*" != substr(h,0,1) ]
}

# Create DNS 'A' record(s):
resource "google_dns_record_set" "d" {
  for_each      = toset(
    var.dns-zone-ref == "" || !var.dns-add-hosts ? [] : local.dnshosts )
  project       = local.zone-proj
  managed_zone  = local.zone-title
  name          = "${each.value}."
  type          = "A"
  ttl           = var.dns-ttl-secs
  rrdatas       = [ local.ip-addr ]
}

