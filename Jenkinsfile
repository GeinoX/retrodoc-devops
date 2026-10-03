pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(
            name: 'BACKEND_VERSION',
            defaultValue: '',
            description: 'Backend Docker image tag. Leave empty to keep the currently deployed version.'
        )

        string(
            name: 'FRONTEND_VERSION',
            defaultValue: '',
            description: 'Frontend Docker image tag. Leave empty to keep the currently deployed version.'
        )
    }

    environment {
        DEPLOY_HOST = '169.58.142.4'
        DEPLOY_DIR = '/opt/retrodoc'

        BACKEND_IMAGE = 'les190/retrodoc-backend'
        FRONTEND_IMAGE = 'les190/retrodoc-frontend'

        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
    }

    stages {

        /*
         * ============================================================
         * CHECKOUT
         * ============================================================
         */

        stage('Checkout') {
            steps {
                checkout scm
            }
        }


        /*
         * ============================================================
         * VALIDATE
         * ============================================================
         */

        stage('Validate') {
            steps {
                sh '''
                    set -eu

                    echo "========================================"
                    echo " Validating Docker Compose configuration"
                    echo "========================================"

                    test -f docker-compose.prod.yml

                    echo "Creating temporary validation environment..."

                    cat > .env <<'EOF'
DB_NAME=validation
DB_USER=validation
DB_PASSWORD=validation
DB_HOST=postgres
DB_PORT=5432

SECRET_KEY=validation-secret-key
DEBUG=False

ALLOWED_HOSTS=localhost
CORS_ALLOWED_ORIGINS=http://localhost
CSRF_TRUSTED_ORIGINS=http://localhost

REDIS_URL=redis://redis:6379/0

EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
EMAIL_HOST=localhost
EMAIL_PORT=25
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
EMAIL_USE_TLS=False
EMAIL_USE_SSL=False
EMAIL_TIMEOUT=10

DEFAULT_FROM_EMAIL=noreply@example.com
SERVER_EMAIL=server@example.com
FRONTEND_BASE_URL=http://localhost:3000

SECURE_HSTS_SECONDS=0
EOF

                    chmod 600 .env

                    cleanup_validation_env() {
                        rm -f .env
                    }

                    trap cleanup_validation_env EXIT

                    echo "Running Docker Compose validation..."

                    BACKEND_VERSION=validation \
                    FRONTEND_VERSION=validation \
                    docker compose \
                        -f docker-compose.prod.yml \
                        config --quiet

                    echo "Docker Compose configuration is valid."
                '''
            }
        }


        /*
         * ============================================================
         * DEPLOY TO CONTABO
         * ============================================================
         */

        stage('Deploy to Contabo') {

            when {
                branch 'main'
            }

            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'contabo-password',
                        usernameVariable: 'SSH_USER',
                        passwordVariable: 'SSH_PASSWORD'
                    )
                ]) {

                    withEnv([
                        "DEPLOY_BACKEND_VERSION=${params.BACKEND_VERSION ?: ''}",
                        "DEPLOY_FRONTEND_VERSION=${params.FRONTEND_VERSION ?: ''}"
                    ]) {

                        sh '''
                            set -eu

                            echo "========================================"
                            echo " Preparing Contabo deployment"
                            echo "========================================"

                            echo "Deploy host: $DEPLOY_HOST"
                            echo "Deploy user: $SSH_USER"
                            echo "Deploy directory: $DEPLOY_DIR"


                            # ====================================================
                            # VERIFY SSHPASS
                            # ====================================================

                            echo "========================================"
                            echo " Verifying sshpass"
                            echo "========================================"

                            command -v sshpass

                            echo "sshpass is available."


                            # ====================================================
                            # TEST SSH CONNECTION
                            # ====================================================

                            echo "========================================"
                            echo " Testing SSH connection to Contabo"
                            echo "========================================"

                            sshpass -p "$SSH_PASSWORD" \
                            ssh \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                -o PubkeyAuthentication=no \
                                -o PreferredAuthentications=password \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "echo 'SSH password authentication successful.'"

                            echo "SSH connection successful."


                            # ====================================================
                            # COPY COMPOSE FILE
                            # ====================================================

                            echo "========================================"
                            echo " Copying production Compose file"
                            echo "========================================"

                            sshpass -p "$SSH_PASSWORD" \
                            scp \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                -o PubkeyAuthentication=no \
                                -o PreferredAuthentications=password \
                                docker-compose.prod.yml \
                                "$SSH_USER@$DEPLOY_HOST:$DEPLOY_DIR/docker-compose.prod.yml"

                            echo "Docker Compose file copied."


                            # ====================================================
                            # DOCKER HUB LOGIN
                            # ====================================================

                            echo "========================================"
                            echo " Logging in to Docker Hub"
                            echo "========================================"

                            printf '%s' "$DOCKERHUB_CREDENTIALS_PSW" | \
                                sshpass -p "$SSH_PASSWORD" \
                                ssh \
                                    -o StrictHostKeyChecking=no \
                                    -o UserKnownHostsFile=/dev/null \
                                    -o PubkeyAuthentication=no \
                                    -o PreferredAuthentications=password \
                                    "$SSH_USER@$DEPLOY_HOST" \
                                    "docker login -u '$DOCKERHUB_CREDENTIALS_USR' --password-stdin"

                            echo "Docker Hub login successful."


                            # ====================================================
                            # REMOTE DEPLOYMENT
                            # ====================================================

                            echo "========================================"
                            echo " Starting remote deployment"
                            echo "========================================"

                            if [ -n "$DEPLOY_BACKEND_VERSION" ]; then
                                echo "Requested backend version: $DEPLOY_BACKEND_VERSION"
                            else
                                echo "Requested backend version: current/latest fallback"
                            fi

                            if [ -n "$DEPLOY_FRONTEND_VERSION" ]; then
                                echo "Requested frontend version: $DEPLOY_FRONTEND_VERSION"
                            else
                                echo "Requested frontend version: current/latest fallback"
                            fi


                            sshpass -p "$SSH_PASSWORD" \
                            ssh \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                -o PubkeyAuthentication=no \
                                -o PreferredAuthentications=password \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "DEPLOY_DIR='$DEPLOY_DIR' BACKEND_IMAGE='$BACKEND_IMAGE' FRONTEND_IMAGE='$FRONTEND_IMAGE' DEPLOY_BACKEND_VERSION='$DEPLOY_BACKEND_VERSION' DEPLOY_FRONTEND_VERSION='$DEPLOY_FRONTEND_VERSION' bash -s" <<'REMOTE_SCRIPT'

set -eu

cd "$DEPLOY_DIR"

echo "========================================"
echo " RetroDoc Production Deployment"
echo "========================================"

echo "Deployment directory:"
echo "$DEPLOY_DIR"


# ============================================================
# CHECK PRODUCTION ENVIRONMENT
# ============================================================

echo "========================================"
echo " Checking production environment"
echo "========================================"

if [ ! -f .env ]; then

    echo "ERROR: Production .env does not exist:"
    echo "$DEPLOY_DIR/.env"

    exit 1

fi

chmod 600 .env

echo "Production environment found."


# ============================================================
# READ CURRENT DEPLOYMENT
# ============================================================

echo "========================================"
echo " Reading current deployment versions"
echo "========================================"

CURRENT_BACKEND=""
CURRENT_FRONTEND=""

if [ -f .deployed_versions ]; then

    CURRENT_BACKEND="$(
        grep '^BACKEND_VERSION=' .deployed_versions \
        | cut -d= -f2- || true
    )"

    CURRENT_FRONTEND="$(
        grep '^FRONTEND_VERSION=' .deployed_versions \
        | cut -d= -f2- || true
    )"

fi

echo "Current backend version: ${CURRENT_BACKEND:-none}"
echo "Current frontend version: ${CURRENT_FRONTEND:-none}"


# ============================================================
# DETERMINE TARGET BACKEND VERSION
# ============================================================

echo "========================================"
echo " Determining backend version"
echo "========================================"

if [ -n "$DEPLOY_BACKEND_VERSION" ]; then

    TARGET_BACKEND="$DEPLOY_BACKEND_VERSION"

elif [ -n "$CURRENT_BACKEND" ]; then

    TARGET_BACKEND="$CURRENT_BACKEND"

else

    TARGET_BACKEND="latest"

fi

echo "Target backend: $TARGET_BACKEND"


# ============================================================
# DETERMINE TARGET FRONTEND VERSION
# ============================================================

echo "========================================"
echo " Determining frontend version"
echo "========================================"

if [ -n "$DEPLOY_FRONTEND_VERSION" ]; then

    TARGET_FRONTEND="$DEPLOY_FRONTEND_VERSION"

elif [ -n "$CURRENT_FRONTEND" ]; then

    TARGET_FRONTEND="$CURRENT_FRONTEND"

else

    TARGET_FRONTEND="latest"

fi

echo "Target frontend: $TARGET_FRONTEND"


# ============================================================
# DISPLAY DEPLOYMENT VERSIONS
# ============================================================

echo "========================================"
echo " Deployment versions"
echo "========================================"

echo "Backend:"
echo "$BACKEND_IMAGE:$TARGET_BACKEND"

echo "Frontend:"
echo "$FRONTEND_IMAGE:$TARGET_FRONTEND"


# ============================================================
# CREATE DEPLOYMENT ENVIRONMENT
# ============================================================

echo "========================================"
echo " Creating deployment version file"
echo "========================================"

cat > .deployment.env <<EOF
BACKEND_VERSION=$TARGET_BACKEND
FRONTEND_VERSION=$TARGET_FRONTEND
EOF

chmod 600 .deployment.env

cleanup_deployment_env() {
    rm -f .deployment.env
}

trap cleanup_deployment_env EXIT


# ============================================================
# VALIDATE PRODUCTION COMPOSE
# ============================================================

echo "========================================"
echo " Validating production Compose"
echo "========================================"

env \
    BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        config --quiet

echo "Production Compose configuration is valid."


# ============================================================
# PULL IMAGES
# ============================================================

echo "========================================"
echo " Pulling Docker images"
echo "========================================"

echo "Pulling backend..."

docker pull \
    "$BACKEND_IMAGE:$TARGET_BACKEND"

echo "Backend image pulled."

echo "Pulling frontend..."

docker pull \
    "$FRONTEND_IMAGE:$TARGET_FRONTEND"

echo "Frontend image pulled."


# ============================================================
# START DATABASE + REDIS
# ============================================================

echo "========================================"
echo " Starting PostgreSQL and Redis"
echo "========================================"

env \
    BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        up -d postgres redis

echo "PostgreSQL and Redis started."

echo "Waiting for infrastructure..."

sleep 10


# ============================================================
# START APPLICATION SERVICES
# ============================================================

echo "========================================"
echo " Starting application services"
echo "========================================"

env \
    BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        up -d backend celery frontend

echo "Backend, Celery and frontend started."

echo "Waiting for application startup..."

sleep 15


# ============================================================
# DATABASE MIGRATIONS
# ============================================================

echo "========================================"
echo " Running Django migrations"
echo "========================================"

env \
    BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        exec -T backend \
        python manage.py migrate --noinput

echo "Database migrations completed."


# ============================================================
# COLLECT STATIC FILES
# ============================================================

echo "========================================"
echo " Collecting static files"
echo "========================================"

env \
    BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        exec -T backend \
        python manage.py collectstatic --noinput

echo "Static files collected."


# ============================================================
# DJANGO PRODUCTION CHECK
# ============================================================

echo "========================================"
echo " Running Django production checks"
echo "========================================"

env \
    BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        exec -T backend \
        python manage.py check --deploy

echo "Django production checks passed."


# ============================================================
# CONTAINER STATUS
# ============================================================

echo "========================================"
echo " Container status"
echo "========================================"

env \
    BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        ps


# ============================================================
# BACKEND HEALTH CHECK
# ============================================================

echo "========================================"
echo " Checking backend"
echo "========================================"

BACKEND_STATUS="$(
    curl \
        -sS \
        -o /dev/null \
        -w '%{http_code}' \
        http://127.0.0.1:8000/ \
        || true
)"

echo "Backend HTTP status: $BACKEND_STATUS"

case "$BACKEND_STATUS" in

    2*|3*|4*)
        echo "Backend is responding."
        ;;

    *)
        echo "ERROR: Backend health check failed."

        docker compose \
            --env-file .env \
            -f docker-compose.prod.yml \
            logs --tail=100 backend

        exit 1
        ;;

esac


# ============================================================
# FRONTEND HEALTH CHECK
# ============================================================

echo "========================================"
echo " Checking frontend"
echo "========================================"

FRONTEND_STATUS="$(
    curl \
        -sS \
        -o /dev/null \
        -w '%{http_code}' \
        http://127.0.0.1:3000/ \
        || true
)"

echo "Frontend HTTP status: $FRONTEND_STATUS"

case "$FRONTEND_STATUS" in

    2*|3*)
        echo "Frontend is healthy."
        ;;

    *)
        echo "ERROR: Frontend health check failed."

        docker compose \
            --env-file .env \
            -f docker-compose.prod.yml \
            logs --tail=100 frontend

        exit 1

        ;;

esac


# ============================================================
# CELERY HEALTH CHECK
# ============================================================

echo "========================================"
echo " Checking Celery"
echo "========================================"

if docker compose \
    --env-file .env \
    -f docker-compose.prod.yml \
    ps --status running celery \
    | grep -q celery
then

    echo "Celery is running."

else

    echo "ERROR: Celery is not running."

    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        logs --tail=100 celery

    exit 1

fi


# ============================================================
# SAVE DEPLOYED VERSIONS
# ============================================================

echo "========================================"
echo " Recording deployed versions"
echo "========================================"

cat > .deployed_versions <<EOF
BACKEND_VERSION=$TARGET_BACKEND
FRONTEND_VERSION=$TARGET_FRONTEND
EOF

chmod 600 .deployed_versions

echo "Deployment versions recorded."


# ============================================================
# FINAL STATUS
# ============================================================

echo ""
echo "========================================"
echo " RETRODOC DEPLOYMENT SUCCESSFUL"
echo "========================================"

echo "Backend:"
echo "  $BACKEND_IMAGE:$TARGET_BACKEND"

echo "Frontend:"
echo "  $FRONTEND_IMAGE:$TARGET_FRONTEND"

echo ""
echo "Services:"

docker compose \
    --env-file .env \
    -f docker-compose.prod.yml \
    ps

echo ""
echo "Deployment completed successfully."

REMOTE_SCRIPT

                    '''
                }
            }
        }
    }


    /*
     * ============================================================
     * POST ACTIONS
     * ============================================================
     */

    post {

        success {
            echo '========================================'
            echo 'RetroDoc production deployment completed successfully.'
            echo '========================================'
        }

        failure {
            echo '========================================'
            echo 'RetroDoc production deployment failed.'
            echo '========================================'
        }

        always {
            echo 'Deployment pipeline finished.'
        }
    }
}