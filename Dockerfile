FROM nginx:1.17.8@sha256:62f787b94e5faddb79f96c84ac0877aaf28fb325bfc3601b9c0934d4c107ba94
ADD ./entrypoint.sh /entrypoint.sh
ENTRYPOINT /entrypoint.sh