#!/bin/bash

mkdir -p ${NGINX_CACHE_PATH}
chown -R nginx:nginx ${NGINX_CACHE_PATH}
STATSD_HOST=${STATSD_HOST-127.0.0.1}

# If statsd hosts is a socket then start socat to do the forwarding
# because nginx-statsd is udp only.
if [[ "${STATSD_HOST}" = *socket* ]]
then
    socat -s -u UDP-RECV:8125 UNIX-SENDTO:${STATSD_HOST}
    # Reset host so socat is used
    STATSD_HOST=127.0.0.1
fi


/bin/cat <<EOF > /etc/nginx/nginx.conf
load_module       modules/ngx_http_statsd_module.so;
user              nginx;
worker_processes  8;
pid               /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    tcp_nopush        on;
    tcp_nodelay       on;
    log_format main '{'
        '"remote_addr": "\$remote_addr",'
        '"time_local": "\$time_local",'
        '"request_time": \$request_time,'
        '"upstream_response_time": "\$upstream_response_time",'
        '"upstream_cache_status": "\$upstream_cache_status",'
        '"request": "\$request",'
        '"request_length": \$request_length,'
        '"status": \$status,'
        '"body_bytes_sent": \$body_bytes_sent'
        '}';
    access_log /dev/stdout main;
    error_log  /dev/stderr warn;
    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}

EOF

/bin/cat <<EOF > /etc/nginx/conf.d/default.conf
proxy_cache_path ${NGINX_CACHE_PATH} levels=1:2 keys_zone=localcache:100m max_size=${NGINX_CACHE_SIZE} inactive=1440m use_temp_path=off;

statsd_server      ${STATSD_HOST};
statsd_sample_rate 100; # 100% of requests

server {
    listen              443 ssl;
    ssl_certificate     ${NGINX_CERT};
    ssl_certificate_key ${NGINX_CERT_KEY};

    resolver 8.8.8.8;

    location /debug/health {
        access_log               off;
        proxy_pass               ${REGISTRY_STATUS_URL};
    }

    location / {
        proxy_http_version       1.1;
        proxy_pass               ${REGISTRY_URL};
        proxy_cache              localcache;
        proxy_cache_revalidate   on;
        proxy_cache_valid        200 302 1440m;
        proxy_cache_use_stale    error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock         on;
        proxy_cache_lock_timeout 5m;
        proxy_intercept_errors   on;
        proxy_cache_background_update on;

        # Forward redirects to the handler below
        error_page 301 302 307 = @handle_redirects;
    }

    # Follows redirects internally and returns the result to the
    # requester.
    location @handle_redirects {
        proxy_http_version       1.1;

        # Follow redirectes
        set \$saved_redirect_location '\$upstream_http_location';
        proxy_pass \$saved_redirect_location;

        # Make sure to cache just the URI and forgo arguments
        proxy_cache_key \$uri;

        proxy_cache              localcache;
        proxy_cache_valid        200 302 1440m;
        proxy_cache_use_stale    error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock         on;
        proxy_cache_lock_timeout 5m;
        proxy_cache_revalidate   on;
        proxy_intercept_errors   on;
        proxy_cache_background_update on;

        # statsd counters
        statsd_count "nginx.cache.\$upstream_cache_status.bytes_sent" \$body_bytes_sent;
        statsd_count "nginx.cache.\$upstream_cache_status.count" 1;
    }
}

# Redirect http to https
server {
    listen 80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

# Monitoring
server {
    listen ${NGINX_STATUS_PORT};
    server_name localhost;

    access_log off;
    allow 127.0.0.1;
    deny all;

    location /nginx_status {
        stub_status;
    }
}
EOF

# Sends cache stats in the background
while : ; do
    CACHE_BYTES=$(du -s ${NGINX_CACHE_PATH} | awk '{ print $1 }')
    echo "nginx.cache.size_bytes:${CACHE_BYTES}|c" | nc -w 1 -u ${STATSD_HOST} 8125
    sleep 10
done &

echo "starting nginx"
/usr/sbin/nginx -g 'daemon off;'
