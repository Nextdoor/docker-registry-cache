FROM nginx:1.17.8@sha256:62f787b94e5faddb79f96c84ac0877aaf28fb325bfc3601b9c0934d4c107ba94 as intermediate
RUN apt-get update && apt-get install --no-install-recommends --no-install-suggests -y gnupg1 ca-certificates curl
RUN apt-key adv --keyserver "pgp.mit.edu" --keyserver-options timeout=10 --recv-keys "573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"
RUN echo "deb https://nginx.org/packages/mainline/debian/ buster nginx" >> /etc/apt/sources.list.d/nginx.list
RUN echo "deb-src https://nginx.org/packages/mainline/debian/ buster nginx" >> /etc/apt/sources.list.d/nginx.list
RUN apt-get update
RUN apt-get build-dep -y nginx=${NGINX_VERSION}-${PKG_RELEASE}
RUN apt-get source -y nginx=${NGINX_VERSION}-${PKG_RELEASE}
RUN mkdir /opt/nginx-statsd
RUN curl https://raw.githubusercontent.com/getsentry/nginx-statsd/ef52718c0e1cf6b52899c89da89b28933eb11557/ngx_http_statsd.c > /opt/nginx-statsd/ngx_http_statsd.c
RUN curl https://raw.githubusercontent.com/getsentry/nginx-statsd/ef52718c0e1cf6b52899c89da89b28933eb11557/config > opt/nginx-statsd/config
RUN cd /nginx-${NGINX_VERSION} && \
	nginx -V 2>&1 | egrep  "^configure" | cut -d: -f2 > /tmp/nginx_build_options.txt && \
	sh -c "./configure $(cat /tmp/nginx_build_options.txt) --add-dynamic-module=/opt/nginx-statsd" && \
	make modules && \
	test -f objs/ngx_http_statsd_module.so

FROM nginx:1.17.8@sha256:62f787b94e5faddb79f96c84ac0877aaf28fb325bfc3601b9c0934d4c107ba94
COPY --from=intermediate /nginx-${NGINX_VERSION}/objs/ngx_http_statsd_module.so /etc/nginx/modules
RUN apt-get update && apt-get install -y netcat && rm -rf /var/lib/apt/lists/*
ADD ./entrypoint.sh /entrypoint.sh
ENTRYPOINT /entrypoint.sh