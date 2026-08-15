# Cloudflare DNS Runbook

## Gereksinimler

- Gecerli Cloudflare API Token (dns_records:read/edit yetkili)
- Dogru Zone ID
- curl ve openssl araclari

## 1) Zone Bulma

```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=ecomaiq.com" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
```

## 2) DNS Kayitlarini Listeleme

```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=100" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
```

## 3) Yeni DNS Kaydi Acma

CNAME ornegi:

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "CNAME",
    "name": "app",
    "content": "ecomaiq.com",
    "ttl": 1,
    "proxied": true
  }'
```

## 4) DNS Kaydi Guncelleme

```bash
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "api",
    "content": "185.189.54.107",
    "ttl": 1,
    "proxied": true
  }'
```

## 5) DNS Kaydi Silme

```bash
curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
```

## 6) SSL Modu Kontrol/Guncelleme

Kontrol:

```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/settings/ssl" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
```

Guncelleme (full):

```bash
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/settings/ssl" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value":"full"}'
```

## 7) Cache Purge

Tum cache:

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/purge_cache" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything": true}'
```

## 8) Dogrulama

DNS:

```bash
dig @1.1.1.1 +short app.ecomaiq.com A
dig @8.8.8.8 +short app.ecomaiq.com A
```

HTTP:

```bash
curl -I https://app.ecomaiq.com
```

TLS:

```bash
echo | openssl s_client -servername app.ecomaiq.com -connect app.ecomaiq.com:443 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```
