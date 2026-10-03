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

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate') {
            steps {
                sh '''
                    set -eu

                    test -f docker-compose.prod.yml

                    echo "Validating production Compose file..."

                    BACKEND_VERSION=validation \
                    FRONTEND_VERSION=validation \
                    DB_NAME=validation \
                    DB_USER=validation \
                    DB_PASSWORD=validation \
                    docker compose -f docker-compose.prod.yml config --quiet

                    echo "Production Compose file is valid."
                '''
            }
        }

        stage('Deploy to Contabo') {
            when {
                branch 'main'
            }

            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'contabo-ssh',
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {

                    sh '''
                        set -eu

                        echo "Preparing deployment..."

                        chmod 600 "$SSH_KEY"

                        mkdir -p ~/.ssh
                        ssh-keyscan -H "$DEPLOY_HOST" >> ~/.ssh/known_hosts 2>/dev/null || true

                        echo "Copying production Compose file to server..."

                        scp \
                            -i "$SSH_KEY" \
                            -o StrictHostKeyChecking=yes \
                            docker-compose.prod.yml \
                            "$SSH_USER@$DEPLOY_HOST:$DEPLOY_DIR/docker-compose.prod.yml"

                        echo "Logging in to Docker Hub on server..."

                        printf '%s' "$DOCKERHUB_CREDENTIALS_PSW" | \
                            ssh \
                                -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=yes \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "docker login -u '$DOCKERHUB_CREDENTIALS_USR' --password-stdin"

                        echo "Starting remote deployment..."

                        ssh \
                            -i "$SSH_KEY" \
                            -o StrictHostKeyChecking=yes \
                            "$SSH_USER@$DEPLOY_HOST" \
                            "BACKEND_VERSION='$BACKEND_VERSION' FRONTEND_VERSION='$FRONTEND_VERSION' DEPLOY_DIR='$DEPLOY_DIR' BACKEND_IMAGE='$BACKEND_IMAGE' FRONTEND_IMAGE='$FRONTEND_IMAGE' bash -s" <<'REMOTE_SCRIPT'

set -eu

cd "$DEPLOY_DIR"

echo "========================================"
echo " RetroDoc Production Deployment"
echo "========================================"

test -f .env

chmod 600 .env

echo "Reading currently deployed versions..."

CURRENT_BACKEND=""
CURRENT_FRONTEND=""

if [ -f .deployed_versions ]; then
    CURRENT_BACKEND="$(grep '^BACKEND_VERSION=' .deployed_versions | cut -d= -f2- || true)"
    CURRENT_FRONTEND="$(grep '^FRONTEND_VERSION=' .deployed_versions | cut -d= -f2- || true)"
fi

# If Jenkins supplied a version, use it.
# Otherwise preserve the currently deployed version.
# If nothing has ever been deployed, use latest.
if [ -n "$BACKEND_VERSION" ]; then
    TARGET_BACKEND="$BACKEND_VERSION"
elif [ -n "$CURRENT_BACKEND" ]; then
    TARGET_BACKEND="$CURRENT_BACKEND"
else
    TARGET_BACKEND="latest"
fi

if [ -n "$FRONTEND_VERSION" ]; then
    TARGET_FRONTEND="$FRONTEND_VERSION"
elif [ -n "$CURRENT_FRONTEND" ]; then
    TARGET_FRONTEND="$CURRENT_FRONTEND"
else
    TARGET_FRONTEND="latest"
fi

echo "Backend image:"
echo "  $BACKEND_IMAGE:$TARGET_BACKEND"

echo "Frontend image:"
echo "  $FRONTEND_IMAGE:$TARGET_FRONTEND"

echo "Creating deployment environment..."

cat > .deployment.env <<EOF
BACKEND_VERSION=$TARGET_BACKEND
FRONTEND_VERSION=$TARGET_FRONTEND
EOF

chmod 600 .deployment.env

echo "Validating Compose configuration..."

env BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        config --quiet

echo "Compose configuration is valid."

echo "Pulling backend image..."

docker pull "$BACKEND_IMAGE:$TARGET_BACKEND"

echo "Pulling frontend image..."

docker pull "$FRONTEND_IMAGE:$TARGET_FRONTEND"

echo "Starting PostgreSQL and Redis..."

env BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        up -d postgres redis

echo "Waiting for infrastructure..."

sleep 10

echo "Starting backend, Celery and frontend..."

env BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        up -d backend celery frontend

echo "Waiting for application containers..."

sleep 15

echo "Running database migrations..."

env BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        exec -T backend \
        python manage.py migrate --noinput

echo "Collecting static files..."

env BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        exec -T backend \
        python manage.py collectstatic --noinput

echo "Running Django deployment checks..."

env BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        exec -T backend \
        python manage.py check --deploy

echo "Checking container status..."

env BACKEND_VERSION="$TARGET_BACKEND" \
    FRONTEND_VERSION="$TARGET_FRONTEND" \
    docker compose \
        --env-file .env \
        -f docker-compose.prod.yml \
        ps

echo "Checking backend..."

BACKEND_STATUS="$(
    curl -sS \
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
        echo "Backend health check failed."
        docker compose --env-file .env -f docker-compose.prod.yml logs --tail=100 backend
        exit 1
        ;;
esac

echo "Checking frontend..."

FRONTEND_STATUS="$(
    curl -sS \
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
        echo "Frontend health check failed."
        docker compose --env-file .env -f docker-compose.prod.yml logs --tail=100 frontend
        exit 1
        ;;
esac

echo "Checking Celery..."

if docker compose \
    --env-file .env \
    -f docker-compose.prod.yml \
    ps --status running celery | grep -q celery; then

    echo "Celery is running."

else

    echo "Celery is not running."
    docker compose --env-file .env -f docker-compose.prod.yml logs --tail=100 celery
    exit 1

fi

echo "Saving deployed versions..."

cat > .deployed_versions <<EOF
BACKEND_VERSION=$TARGET_BACKEND
FRONTEND_VERSION=$TARGET_FRONTEND
EOF

chmod 600 .deployed_versions

rm -f .deployment.env

echo "========================================"
echo " Deployment completed successfully"
echo "========================================"

echo "Backend:  $BACKEND_IMAGE:$TARGET_BACKEND"
echo "Frontend: $FRONTEND_IMAGE:$TARGET_FRONTEND"

REMOTE_SCRIPT
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'RetroDoc production deployment completed successfully.'
        }

        failure {
            echo 'RetroDoc production deployment failed.'
        }

        always {
            sh '''
                rm -f ~/.ssh/known_hosts 2>/dev/null || true
            '''
        }
    }
}
