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
                sh '''
                    set -eu

                    test -f docker-compose.prod.yml

                    echo "Backend image:  les190/retrodoc-backend:$BACKEND_VERSION"
                    echo "Frontend image: les190/retrodoc-frontend:$FRONTEND_VERSION"
                '''
            }
        }

        stage('Deploy') {
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

                        ssh \
                            -i "$SSH_KEY" \
                            -o BatchMode=yes \
                            -o StrictHostKeyChecking=accept-new \
                            "$SSH_USER@$DEPLOY_HOST" \
                            "mkdir -p '$DEPLOY_DIR'"

                        scp \
                            -i "$SSH_KEY" \
                            -o BatchMode=yes \
                            -o StrictHostKeyChecking=accept-new \
                            docker-compose.prod.yml \
                            "$SSH_USER@$DEPLOY_HOST:$DEPLOY_DIR/docker-compose.prod.yml"

                        ssh \
                            -i "$SSH_KEY" \
                            -o BatchMode=yes \
                            -o StrictHostKeyChecking=accept-new \
                            "$SSH_USER@$DEPLOY_HOST" <<EOF

set -eu

cd '$DEPLOY_DIR'

export BACKEND_VERSION='$BACKEND_VERSION'
export FRONTEND_VERSION='$FRONTEND_VERSION'

echo "========================================"
echo "Deploying RetroDoc"
echo "Backend : \$BACKEND_VERSION"
echo "Frontend: \$FRONTEND_VERSION"
echo "========================================"

docker pull "les190/retrodoc-backend:\$BACKEND_VERSION"
docker pull "les190/retrodoc-frontend:\$FRONTEND_VERSION"

echo "Starting PostgreSQL and Redis..."

docker compose \
    -f docker-compose.prod.yml \
    up -d postgres redis

sleep 5

echo "Starting backend..."

docker compose \
    -f docker-compose.prod.yml \
    up -d backend

sleep 5

echo "Running migrations..."

docker compose \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py migrate --noinput

echo "Collecting static files..."

docker compose \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py collectstatic --noinput

echo "Starting application services..."

docker compose \
    -f docker-compose.prod.yml \
    up -d --force-recreate backend celery frontend

echo "Running Django deployment checks..."

docker compose \
    -f docker-compose.prod.yml \
    exec -T backend \
    python manage.py check --deploy

echo "Checking containers..."

docker compose \
    -f docker-compose.prod.yml \
    ps

echo "Checking backend..."

BACKEND_STATUS=\$(curl \
    -s \
    -o /dev/null \
    -w '%{http_code}' \
    http://127.0.0.1:8000/ || true)

if [ "\$BACKEND_STATUS" = "000" ]; then
    echo "Backend is not responding."

    docker compose \
        -f docker-compose.prod.yml \
        logs --tail=100 backend

    exit 1
fi

echo "Backend responded with HTTP \$BACKEND_STATUS"

echo "Checking frontend..."

curl -fsS \
    http://127.0.0.1:3000/ \
    >/dev/null

echo "Frontend HTTP check passed."

echo "========================================"
echo "RetroDoc deployment successful"
echo "Backend : \$BACKEND_VERSION"
echo "Frontend: \$FRONTEND_VERSION"
echo "========================================"

EOF
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'RetroDoc production deployment succeeded.'
        }

        failure {
            echo 'RetroDoc production deployment failed.'
        }
    }
}