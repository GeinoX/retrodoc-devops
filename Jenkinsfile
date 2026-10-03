pipeline {
    agent any

    parameters {
        string(
            name: 'BACKEND_VERSION',
            defaultValue: 'latest',
            description: 'Docker tag for the backend image'
        )

        string(
            name: 'FRONTEND_VERSION',
            defaultValue: 'latest',
            description: 'Docker tag for the frontend image'
        )
    }

    environment {
        DEPLOY_HOST = '169.58.142.4'
        DEPLOY_DIR = '/opt/retrodoc'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate') {
            steps {
                script {

                    def backendVersion =
                        params.BACKEND_VERSION?.trim() ?: 'latest'

                    def frontendVersion =
                        params.FRONTEND_VERSION?.trim() ?: 'latest'

                    echo "Backend version: ${backendVersion}"
                    echo "Frontend version: ${frontendVersion}"

                    sh """
                        set -eu

                        test -f docker-compose.prod.yml

                        echo "Production compose file found."

                        trap 'rm -f .env' EXIT

                        cat > .env <<'EOF'
DB_NAME=retrodoc_validation
DB_USER=retrodoc_validation
DB_PASSWORD=validation_password
BACKEND_VERSION=${backendVersion}
FRONTEND_VERSION=${frontendVersion}
EOF

                        docker compose \
                            -f docker-compose.prod.yml \
                            config >/dev/null

                        echo "Production Docker Compose configuration is valid."

                        rm -f .env
                        trap - EXIT
                    """
                }
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }

            steps {
                script {

                    def backendVersion =
                        params.BACKEND_VERSION?.trim() ?: 'latest'

                    def frontendVersion =
                        params.FRONTEND_VERSION?.trim() ?: 'latest'

                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: 'contabo-ssh',
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        )
                    ]) {

                        sh """
                            set -eu

                            echo "Deploying RetroDoc..."

                            echo "Backend:  les190/retrodoc-backend:${backendVersion}"
                            echo "Frontend: les190/retrodoc-frontend:${frontendVersion}"

                            ssh \
                                -i "\$SSH_KEY" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=accept-new \
                                "\$SSH_USER@\$DEPLOY_HOST" \
                                "mkdir -p '$DEPLOY_DIR'"

                            scp \
                                -i "\$SSH_KEY" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=accept-new \
                                docker-compose.prod.yml \
                                "\$SSH_USER@\$DEPLOY_HOST:\$DEPLOY_DIR/docker-compose.prod.yml"

                            ssh \
                                -i "\$SSH_KEY" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=accept-new \
                                "\$SSH_USER@\$DEPLOY_HOST" \
                                "cd '$DEPLOY_DIR' && \
                                 test -f .env"

                            ssh \
                                -i "\$SSH_KEY" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=accept-new \
                                "\$SSH_USER@\$DEPLOY_HOST" <<EOF

set -eu

cd '$DEPLOY_DIR'

export BACKEND_VERSION='${backendVersion}'
export FRONTEND_VERSION='${frontendVersion}'

echo "Checking Docker..."

docker --version
docker compose version

echo "Pulling exact backend image..."

docker pull "les190/retrodoc-backend:\$BACKEND_VERSION"

echo "Pulling exact frontend image..."

docker pull "les190/retrodoc-frontend:\$FRONTEND_VERSION"

echo "Starting PostgreSQL and Redis..."

docker compose \
    -f docker-compose.prod.yml \
    up -d postgres redis

echo "Waiting for PostgreSQL and Redis..."

sleep 10

echo "Starting backend..."

docker compose \
    -f docker-compose.prod.yml \
    up -d backend

echo "Waiting for backend..."

sleep 10

echo "Running database migrations..."

docker compose \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py migrate --noinput

echo "Collecting static files..."

docker compose \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py collectstatic --noinput

echo "Running Django deployment checks..."

docker compose \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py check --deploy

echo "Starting Celery..."

docker compose \
    -f docker-compose.prod.yml \
    up -d --force-recreate celery

echo "Starting frontend..."

docker compose \
    -f docker-compose.prod.yml \
    up -d --force-recreate frontend

echo "Waiting for services..."

sleep 10

echo "Container status:"

docker compose \
    -f docker-compose.prod.yml \
    ps

echo "Checking frontend..."

curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:3000/ \
    >/dev/null

echo "Frontend health check passed."

echo "Checking backend..."

BACKEND_STATUS=\$(curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    http://127.0.0.1:8000/ || true)

echo "Backend HTTP status: \$BACKEND_STATUS"

if [ "\$BACKEND_STATUS" = "000" ]; then

    echo "Backend is unreachable."

    docker compose \
        -f docker-compose.prod.yml \
        logs \
        --tail=150 \
        backend

    exit 1

fi

echo "Backend health check passed."

echo "Checking Celery..."

CELERY_STATUS=\$(docker inspect \
    --format='{{.State.Running}}' \
    retrodoc-celery 2>/dev/null || true)

if [ "\$CELERY_STATUS" != "true" ]; then

    echo "Celery is not running."

    docker compose \
        -f docker-compose.prod.yml \
        logs \
        --tail=150 \
        celery

    exit 1

fi

echo "Celery health check passed."

echo "Saving deployed versions..."

cat > .deployed_versions <<VERSION_EOF
BACKEND_VERSION=\$BACKEND_VERSION
FRONTEND_VERSION=\$FRONTEND_VERSION
DEPLOYED_AT=\$(date -u '+%Y-%m-%dT%H:%M:%SZ')
VERSION_EOF

echo "Deployment successful."

cat .deployed_versions

EOF
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            echo '======================================'
            echo 'RetroDoc deployment SUCCESSFUL'
            echo '======================================'
        }

        failure {
            echo '======================================'
            echo 'RetroDoc deployment FAILED'
            echo '======================================'

            echo 'Check the deployment logs and container status.'
        }

        always {
            echo 'RetroDoc DevOps pipeline finished.'
        }
    }
}