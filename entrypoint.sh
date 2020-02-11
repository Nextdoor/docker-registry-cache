#!/bin/bash

mkdir -p ${NGINX_CACHE_PATH}
chown -R nginx:nginx ${NGINX_CACHE_PATH}


/bin/cat <<EOF > /etc/nginx/nginx.conf
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

    log_format log  '{'
        '"remote_addr": "\$remote_addr",'
        '"remote_user": "\$remote_user",'
        '"server_name": "\$server_name",'
        '"server_port": "\$server_port",'
        '"host": "\$host",'
        '"time_local": "\$time_local",'
        '"context_id": "\$sent_http_context_id",'
        '"request_time": \$request_time,'
        '"upstream_response_time": \$upstream_response_time,'
        '"request": "\$request",'
        '"request_length": \$request_length,'
        '"status": \$status,'
        '"body_bytes_sent": \$body_bytes_sent,'
        '"http_referer": "\$http_referer",'
        '"http_x_forwarded_for": "\$http_x_forwarded_for",'
        '"args": "\$args",'
        '"event_name": "NGINX_LOG"'
        '}';

    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}
EOF


/bin/cat <<EOF > /etc/nginx/conf.d/default.conf
proxy_cache_path ${NGINX_CACHE_PATH} levels=1:2 keys_zone=localcache:100m max_size=${NGINX_CACHE_SIZE} use_temp_path=off;

server {
    listen              ${NGINX_PORT} ssl;
    ssl_certificate     ${NGINX_CERT};
    ssl_certificate_key ${NGINX_CERT_KEY};

    resolver 8.8.8.8;

    location /debug/health {
        proxy_pass               ${REGISTRY_STATUS_URL};
    }

    location / {
        proxy_http_version       1.1;
        proxy_pass               ${REGISTRY_URL};
        proxy_cache              localcache;
        proxy_cache_revalidate   on;
        proxy_cache_valid        200 302 60m;
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
        proxy_cache_valid        200 302 60m;
        proxy_cache_use_stale    error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock         on;
        proxy_cache_lock_timeout 5m;
        proxy_cache_revalidate   on;
        proxy_intercept_errors   on;
        proxy_cache_background_update on;

    }
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

echo "starting nginx"
/usr/sbin/nginx -g 'daemon off;'
