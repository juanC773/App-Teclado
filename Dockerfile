FROM nginx:alpine

# Copiar archivos de la app al directorio de Nginx
COPY index.html /usr/share/nginx/html/
COPY script.js /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/

# Exponer el puerto 80
EXPOSE 80

# Nginx se inicia automáticamente
CMD ["nginx", "-g", "daemon off;"]
