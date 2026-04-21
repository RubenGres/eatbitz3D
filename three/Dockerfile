FROM nginx:alpine

COPY index.html styles.css /usr/share/nginx/html/
COPY src /usr/share/nginx/html/src
COPY vendor /usr/share/nginx/html/vendor
COPY data /usr/share/nginx/html/data
COPY assets /usr/share/nginx/html/assets
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
