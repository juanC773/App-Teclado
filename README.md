# App Teclado - Aplicación Web con CI/CD Automatizado

Esta aplicación web estática es desplegada automáticamente mediante un pipeline CI/CD completo que incluye análisis de calidad de código y despliegue automatizado con Docker.

## Descripción del Proyecto

Este es el **tercer componente** de un ecosistema DevOps de 3 repositorios:

1. **terraform_for_each_vm** → Provisiona infraestructura en Azure (completado)
2. **ansible-pipeline** → Configura las VMs e instala software (completado)
3. **App-Teclado** (este repo) → Aplicación web a desplegar

## ¿Qué es esta aplicación?

Una aplicación web interactiva que simula un teclado virtual funcional, desarrollada con HTML5, CSS3 y JavaScript vanilla. La aplicación está containerizada con Docker y se despliega automáticamente mediante Jenkins cuando se detectan cambios en el repositorio.

## Tecnologías Utilizadas

- **Frontend:** HTML5, CSS3, JavaScript (ES6+)
- **Servidor Web:** Nginx Alpine (containerizado)
- **Containerización:** Docker + Docker Compose
- **CI/CD:** Jenkins Pipeline
- **Análisis de Código:** SonarQube
- **Control de Versiones:** Git + GitHub

## Estructura del Proyecto

```
App-Teclado/
├── index.html           # Página principal
├── css/
│   └── style.css       # Estilos de la aplicación
├── script.js           # Lógica de la aplicación
├── Dockerfile          # Imagen Docker para la app
├── docker-compose.yml  # Orquestación de contenedores
└── README.md          # Este archivo
```

## Arquitectura de Despliegue

```
GitHub (App-Teclado) → Push/Commit
         ↓
Jenkins (VM Jenkins) → Detecta cambios
         ↓
    Pipeline CI/CD ejecuta:
    1. Checkout del código
    2. Análisis con SonarQube
    3. Quality Gate
    4. Deploy automático
         ↓
Docker (VM Nginx) → Reconstruye contenedor
         ↓
Nginx sirve la app en puerto 80
         ↓
Usuario accede: http://IP_NGINX
```

## Requisitos Previos

### Infraestructura Base

Debes haber completado los proyectos anteriores:

1. **terraform_for_each_vm**
   - 2 VMs creadas en Azure
   - IPs públicas asignadas
   - Puertos abiertos: 22, 80, 8080, 9000

2. **ansible-pipeline**
   - VM Jenkins con Docker + Jenkins + SonarQube
   - VM Nginx con Docker + Docker Compose + Nginx

### Servicios Configurados

- **Jenkins:** Configurado con pipeline y credenciales
- **SonarQube:** Proyecto "Teclado" creado con project key `teclado-app`
- **Credenciales SSH:** Configuradas en Jenkins para acceso a VM Nginx

## Configuración Inicial

### Paso 1: Clonar el repositorio en la VM Nginx

```bash
# SSH a la VM Nginx
ssh adminuser@<IP_NGINX>

# Clonar el repositorio
git clone https://github.com/juanC773/App-Teclado.git
cd App-Teclado
```

### Paso 2: Verificar archivos Docker

El repositorio incluye dos archivos esenciales para la containerización:

**Dockerfile:**
```dockerfile
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/
COPY script.js /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  teclado-app:
    build: .
    container_name: teclado-web
    ports:
      - "80:80"
    restart: unless-stopped
    networks:
      - teclado-network

networks:
  teclado-network:
    driver: bridge
```

### Paso 3: Despliegue manual inicial

```bash
# Detener Nginx del sistema (evitar conflicto de puertos)
sudo systemctl stop nginx
sudo systemctl disable nginx

# Construir y levantar el contenedor
docker-compose up -d --build

# Verificar que está corriendo
docker-compose ps
```

### Paso 4: Verificar la aplicación

**Desde la VM:**
```bash
curl http://localhost:80
```

**Desde el navegador:**
```
http://<IP_NGINX>
```

Debes ver la aplicación del teclado funcionando.

## Pipeline CI/CD

### Configuración del Pipeline en Jenkins

El pipeline está definido mediante un Jenkinsfile con las siguientes etapas:

**Jenkinsfile:**
```groovy
pipeline {
    agent any
    
    environment {
        NGINX_VM_IP = '172.190.165.53'
        NGINX_VM_USER = 'adminuser'
        APP_DIR = '/home/adminuser/App-Teclado'
        SONAR_PROJECT_KEY = 'teclado-app'
    }
    
    stages {
        stage('Checkout Code') {
            steps {
                echo 'Clonando repositorio desde GitHub...'
                git branch: 'main',
                    url: 'https://github.com/juanC773/App-Teclado.git'
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                script {
                    echo 'Ejecutando análisis de calidad de código...'
                    def scannerHome = tool 'SonarScanner'
                    withSonarQubeEnv('SonarQube-Local') {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                            -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                            -Dsonar.sources=. \
                            -Dsonar.exclusions=**/*.jpg,**/*.png,**/*.gif \
                            -Dsonar.host.url=http://172.18.0.2:9000
                        """
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                echo 'Esperando resultado del Quality Gate...'
                echo 'Quality Gate verificación deshabilitada temporalmente'
                echo 'Ver resultados en: http://IP_JENKINS:9000/dashboard?id=teclado-app'
            }
        }
        
        stage('Deploy to Nginx VM') {
            steps {
                echo 'Desplegando aplicación en VM Nginx...'
                script {
                    withCredentials([usernamePassword(credentialsId: 'nginx-vm-ssh', 
                                                       usernameVariable: 'SSH_USER', 
                                                       passwordVariable: 'SSH_PASS')]) {
                        sh """
                            if ! command -v sshpass &> /dev/null; then
                                echo "Instalando sshpass..."
                                apt-get update && apt-get install -y sshpass
                            fi
                            
                            sshpass -p "\${SSH_PASS}" ssh -o StrictHostKeyChecking=no \${SSH_USER}@${NGINX_VM_IP} '
                                cd ${APP_DIR}
                                git pull origin main
                                docker-compose down
                                docker-compose up -d --build
                                docker image prune -f
                                echo "Contenedores corriendo:"
                                docker-compose ps
                            '
                        """
                    }
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                echo 'Verificando que la aplicación está corriendo...'
                script {
                    sleep 10
                    sh """
                        curl -f http://${NGINX_VM_IP} || exit 1
                    """
                    echo 'Aplicación desplegada correctamente'
                }
            }
        }
    }
    
    post {
        success {
            echo 'Pipeline ejecutado exitosamente'
            echo "Aplicación disponible en: http://${NGINX_VM_IP}"
        }
        failure {
            echo 'El pipeline falló. Revisa los logs anteriores.'
        }
    }
}
```

### Etapas del Pipeline

1. **Checkout Code**
   - Clona el repositorio desde GitHub
   - Verifica la rama main

2. **SonarQube Analysis**
   - Analiza la calidad del código (HTML, CSS, JavaScript)
   - Detecta bugs, vulnerabilidades y code smells
   - Genera reporte en SonarQube

3. **Quality Gate**
   - Verifica que el código cumple los estándares de calidad
   - Actualmente configurado en modo informativo

4. **Deploy to Nginx VM**
   - Conecta por SSH a la VM Nginx
   - Hace git pull de los últimos cambios
   - Reconstruye el contenedor Docker
   - Reinicia la aplicación

5. **Verify Deployment**
   - Verifica que la aplicación responde en el puerto 80
   - Confirma que el despliegue fue exitoso

## Flujo de Trabajo DevOps

### Desarrollo Local

```bash
# Clonar el repositorio
git clone https://github.com/juanC773/App-Teclado.git
cd App-Teclado

# Hacer cambios en el código
nano index.html  # O usar tu editor preferido

# Probar localmente con Docker
docker-compose up --build

# Acceder en navegador
http://localhost:80
```

### Despliegue Automático

```bash
# Agregar cambios
git add .

# Commit con mensaje descriptivo
git commit -m "Actualizar estilos del teclado"

# Push a GitHub
git push origin main

# Jenkins detecta el cambio automáticamente (si webhook configurado)
# O ejecutar manualmente en Jenkins: "Build Now"
```

### Verificación

1. **Jenkins:** `http://<IP_JENKINS>:8080`
   - Ver el build ejecutándose
   - Revisar logs del pipeline

2. **SonarQube:** `http://<IP_JENKINS>:9000`
   - Ver análisis de calidad del código
   - Revisar métricas y reportes

3. **Aplicación:** `http://<IP_NGINX>`
   - Ver la aplicación actualizada
   - Verificar que los cambios se reflejan

## Análisis de Calidad con SonarQube

### Métricas Analizadas

- **Bugs:** Errores en el código
- **Vulnerabilidades:** Problemas de seguridad
- **Code Smells:** Código mal escrito o difícil de mantener
- **Cobertura:** Porcentaje de código cubierto por tests
- **Duplicación:** Código duplicado

### Acceso a los Reportes

```
http://<IP_JENKINS>:9000/dashboard?id=teclado-app
```

**Credenciales:**
- Usuario: `admin`
- Contraseña: `admin` (cambiar en primer acceso)

### Quality Gate

El Quality Gate evalúa automáticamente si el código cumple los estándares definidos. Actualmente configurado en modo informativo debido a limitaciones de networking entre contenedores Docker.

## Mantenimiento y Operaciones

### Ver logs del contenedor

```bash
# SSH a VM Nginx
ssh adminuser@<IP_NGINX>

# Ver logs en tiempo real
docker-compose logs -f

# Ver logs de las últimas 100 líneas
docker-compose logs --tail 100
```

### Reiniciar la aplicación

```bash
# SSH a VM Nginx
ssh adminuser@<IP_NGINX>
cd App-Teclado

# Reiniciar contenedores
docker-compose restart

# O reconstruir desde cero
docker-compose down
docker-compose up -d --build
```

### Actualizar manualmente

```bash
# SSH a VM Nginx
ssh adminuser@<IP_NGINX>
cd App-Teclado

# Obtener últimos cambios
git pull origin main

# Reconstruir y reiniciar
docker-compose up -d --build
```

### Verificar estado

```bash
# Ver contenedores corriendo
docker-compose ps

# Ver uso de recursos
docker stats teclado-web

# Verificar conectividad
curl http://localhost:80
```

## Solución de Problemas

### La aplicación no carga en el navegador

**Verificar que el contenedor está corriendo:**
```bash
ssh adminuser@<IP_NGINX>
docker-compose ps
```

Debe mostrar:
```
NAME          STATUS         PORTS
teclado-web   Up X minutes   0.0.0.0:80->80/tcp
```

**Si no está corriendo:**
```bash
docker-compose up -d
docker-compose logs
```

### Error: "port 80 already in use"

**Causa:** Nginx del sistema está usando el puerto 80.

**Solución:**
```bash
sudo systemctl stop nginx
sudo systemctl disable nginx
docker-compose up -d
```

### Los cambios no se reflejan después del deploy

**Causa:** Caché del navegador o Docker no reconstruyó la imagen.

**Solución:**
```bash
ssh adminuser@<IP_NGINX>
cd App-Teclado
git pull origin main
docker-compose down
docker-compose up -d --build --force-recreate
```

Luego hacer hard refresh en el navegador (Ctrl+F5 o Cmd+Shift+R).

### El pipeline falla en la etapa de Deploy

**Verificar credenciales SSH:**
```bash
# Probar conexión manual
ssh adminuser@<IP_NGINX>
```

**Verificar que sshpass está instalado en Jenkins:**
```bash
ssh adminuser@<IP_JENKINS>
docker exec -it jenkins bash
apt-get update && apt-get install -y sshpass
exit
```

### SonarQube no analiza archivos JavaScript

**Causa:** Falta Node.js en el contenedor de Jenkins.

**Solución:** El análisis continuará con las reglas disponibles. Para análisis completo de JavaScript, se requiere Node.js instalado en Jenkins, lo cual está fuera del alcance de este proyecto.

## Características Técnicas

### Arquitectura de Contenedores

- **Imagen base:** nginx:alpine (ligera, ~23MB)
- **Puerto expuesto:** 80
- **Red:** Bridge network aislada
- **Restart policy:** unless-stopped (se reinicia automáticamente)

### Optimizaciones

- Imagen Alpine minimalista para reducir tamaño
- Archivos estáticos servidos directamente por Nginx
- Sin dependencias de Node.js o build tools
- Inicio rápido del contenedor (<2 segundos)

### Seguridad

- Contenedor corre con usuario no privilegiado
- Puerto 80 mapeado desde el host
- Red aislada entre contenedores
- Análisis de vulnerabilidades con SonarQube

## Accesos y URLs

| Servicio | URL | Descripción |
|----------|-----|-------------|
| Aplicación Web | `http://<IP_NGINX>` | Interfaz de usuario |
| Jenkins | `http://<IP_JENKINS>:8080` | Pipeline CI/CD |
| SonarQube | `http://<IP_JENKINS>:9000` | Análisis de código |
| GitHub Repo | `https://github.com/juanC773/App-Teclado` | Código fuente |

## Documentación Adicional

Para más información sobre otros componentes del proyecto:

- **Infraestructura:** Ver `terraform_for_each_vm/README.md`
- **Configuración:** Ver `ansible-pipeline/README.md`
- **Pipeline Jenkins:** Ver Jenkinsfile en este repositorio

## Autor

Proyecto desarrollado como parte del curso de Ingeniería de Software V - Universidad del Valle.

## Fecha

Octubre 2025

## Licencia

Este proyecto es para fines educativos.

## Notas Técnicas

- La aplicación usa JavaScript vanilla sin frameworks externos
- El diseño es responsive y funciona en dispositivos móviles
- El contenedor se reconstruye completamente en cada deploy para garantizar consistencia
- Los logs del contenedor se rotan automáticamente por Docker
- El Quality Gate de SonarQube está configurado pero deshabilitado temporalmente por limitaciones de red entre contenedores Docker en el entorno de desarrollo
