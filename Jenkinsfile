pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()

        buildDiscarder(
            logRotator(
                numToKeepStr: '20'
            )
        )
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

                    # We only validate syntax here.
                    # The real .env exists on the deployment server.
                    docker compose \
                        -f docker-compose.prod.yml \
                        config --quiet

                    echo "Compose configuration is valid."
                '''
            }
        }

        stage('Deploy to Contabo') {
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

                        chmod 600 "$SSH_KEY"

                        echo "======================================"
                        echo "Preparing Contabo deployment"
                        echo "======================================"

                        ssh \
                            -i "$SSH_KEY" \
                            -o StrictHostKeyChecking=no \
                            "$SSH_USER@$DEPLOY_HOST" \
                            "mkdir -p '$DEPLOY_DIR'"

                        echo "Uploading production Compose file..."

                        scp \
                            -i "$SSH_KEY" \
                            -o StrictHostKeyChecking=no \
                            docker-compose.prod.yml \
                            "$SSH_USER@$DEPLOY_HOST:$DEPLOY_DIR/docker-compose.prod.yml"

                        echo "Logging into Docker Hub on deployment server..."

                        printf '%s' "$DOCKERHUB_CREDENTIALS_PSW" |
                            ssh \
                                -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=no \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "docker login -u '$DOCKERHUB_CREDENTIALS_USR' --password-stdin"

                        echo "Starting remote deployment..."

                        ssh \
                            -i "$SSH_KEY" \
                            -o StrictHostKeyChecking=no \
                            "$SSH_USER@$DEPLOY_HOST" \
                            "BACKEND_VERSION='${BACKEND_VERSION}' \
                             FRONTEND_VERSION='${FRONTEND_VERSION}' \
                             DEPLOY_DIR='$DEPLOY_DIR' \
                             BACKEND_IMAGE='$BACKEND_IMAGE' \
                             FRONTEND_IMAGE='$FRONTEND_IMAGE' \
                             bash -s" <<'REMOTE_SCRIPT'

set -eu

cd "$DEPLOY_DIR"

STATE_FILE="$DEPLOY_DIR/.deployed_versions"
DEPLOY_ENV="$DEPLOY_DIR/.deployment.env"

echo
echo "======================================"
echo "Reading currently deployed versions"
echo "======================================"

CURRENT_BACKEND=""
CURRENT_FRONTEND=""

if [ -f "$STATE_FILE" ]; then
    CURRENT_BACKEND="$(awk -F= '$1=="BACKEND_VERSION"{print $2}' "$STATE_FILE" || true)"
    CURRENT_FRONTEND="$(awk -F= '$1=="FRONTEND_VERSION"{print $2}' "$STATE_FILE" || true)"
fi

echo "Current backend:  ${CURRENT_BACKEND:-none}"
echo "Current frontend: ${CURRENT_FRONTEND:-none}"

#
# If Jenkins supplied a version, deploy it.
# Otherwise retain the currently deployed version.
#
BACKEND_VERSION="${BACKEND_VERSION:-$CURRENT_BACKEND}"
FRONTEND_VERSION="${FRONTEND_VERSION:-$CURRENT_FRONTEND}"

#
# Initial deployment fallback.
#
BACKEND_VERSION="${BACKEND_VERSION:-latest}"
FRONTEND_VERSION="${FRONTEND_VERSION:-latest}"

echo
echo "======================================"
echo "Target versions"
echo "======================================"

echo "Backend:  $BACKEND_VERSION"
echo "Frontend: $FRONTEND_VERSION"

#
# The deployment env contains only image versions.
# Application secrets remain in /opt/retrodoc/.env.
#
cat > "$DEPLOY_ENV" <<EOF
BACKEND_VERSION=$BACKEND_VERSION
FRONTEND_VERSION=$FRONTEND_VERSION
EOF

chmod 600 "$DEPLOY_ENV"

echo
echo "======================================"
echo "Validating deployment environment"
echo "======================================"

test -f "$DEPLOY_DIR/.env"

echo "Production .env found."

echo
echo "======================================"
echo "Pulling backend image"
echo "======================================"

docker pull "$BACKEND_IMAGE:$BACKEND_VERSION"

echo
echo "======================================"
echo "Pulling frontend image"
echo "======================================"

docker pull "$FRONTEND_IMAGE:$FRONTEND_VERSION"

echo
echo "======================================"
echo "Validating Docker Compose"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    config --quiet

echo "Compose validation successful."

echo
echo "======================================"
echo "Starting PostgreSQL and Redis"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    up -d postgres redis

echo
echo "Waiting for infrastructure..."
sleep 10

echo
echo "======================================"
echo "Starting application services"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    up -d backend celery frontend

echo
echo "Waiting for application startup..."
sleep 15

echo
echo "======================================"
echo "Running database migrations"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py migrate --noinput

echo
echo "======================================"
echo "Collecting static files"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py collectstatic --noinput

echo
echo "======================================"
echo "Django deployment checks"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py check --deploy

echo
echo "======================================"
echo "Container status"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    ps

echo
echo "======================================"
echo "Backend health check"
echo "======================================"

if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 15 \
    http://127.0.0.1:8000/ \
    >/dev/null
then
    echo "Backend health check: OK"
else
    echo "Backend health check: FAILED"

    docker compose \
        --env-file "$DEPLOY_DIR/.env" \
        --env-file "$DEPLOY_ENV" \
        -f docker-compose.prod.yml \
        logs --tail=100 backend

    exit 1
fi

echo
echo "======================================"
echo "Frontend health check"
echo "======================================"

if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 15 \
    http://127.0.0.1:3000/ \
    >/dev/null
then
    echo "Frontend health check: OK"
else
    echo "Frontend health check: FAILED"

    docker compose \
        --env-file "$DEPLOY_DIR/.env" \
        --env-file "$DEPLOY_ENV" \
        -f docker-compose.prod.yml \
        logs --tail=100 frontend

    exit 1
fi

echo
echo "======================================"
echo "Celery verification"
echo "======================================"

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    ps celery

docker compose \
    --env-file "$DEPLOY_DIR/.env" \
    --env-file "$DEPLOY_ENV" \
    -f docker-compose.prod.yml \
    logs --tail=30 celery

echo
echo "======================================"
echo "Saving deployed versions"
echo "======================================"

cat > "$STATE_FILE" <<EOF
BACKEND_VERSION=$BACKEND_VERSION
FRONTEND_VERSION=$FRONTEND_VERSION
DEPLOYED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

chmod 600 "$STATE_FILE"

rm -f "$DEPLOY_ENV"

echo
echo "======================================"
echo "PRODUCTION DEPLOYMENT SUCCESSFUL"
echo "======================================"

echo "Backend:  $BACKEND_VERSION"
echo "Frontend: $FRONTEND_VERSION"
echo "Deployed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

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
    }
}
