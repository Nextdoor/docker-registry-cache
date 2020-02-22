# docker-registry-cache
An nginx cache to be placed in front of a docker registry


Env Var | Description
--- | ---
`NGINX_CACHE_PATH` | Location to store cached content
`NGINX_CACHE_SIZE` | Size of cache. Eg `1024m`.
`NGINX_CERT`       | SSL certificate in pem format to use.
`NGINX_CERT_KEY`   | SSL certificate key in pem format to use.
`REGISTRY_URL`     | Docker registry url to proxy pass through to. Eg. `http://localhost:5000`
`REGISTRY_STATUS_URL` | Registry status url. Eg. `http://localhost:5001/debug/health`
`NGINX_STATUS_PORT`| Port to expose `/nginx_status` on. Note this is only accessible from `127.0.0.1`
`STATSD_HOST`      | Host to send statsd metrics to.