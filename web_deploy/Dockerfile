FROM nginx:alpine

# nginx.conf 覆盖默认配置（针对 Flutter SPA）
COPY nginx.conf /etc/nginx/conf.d/default.conf

# CI 预构建的 Flutter Web 产物（来自 cp -r build/web web_deploy/build-web）
COPY build-web/ /usr/share/nginx/html/

# nginx alpine 默认监听 80
EXPOSE 80
