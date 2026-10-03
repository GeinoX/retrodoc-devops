pipeline {
    agent any

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

                    echo "Validating RetroDoc production configuration..."

                    test -f docker-compose.prod.yml

                    docker compose -f docker-compose.prod.yml config >/dev/null

                    echo "Production Docker Compose configuration is valid."
                '''
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }

            steps {
                script {
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: 'contabo-ssh',
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        )
                    ]) {

                        sh '''
                            set -eu

                            echo "Preparing deployment directory..."

                            ssh \
                                -i "$SSH_KEY" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=accept-new \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "mkdir -p '$DEPLOY_DIR'"

                            echo "Uploading production Docker Compose file..."

                            scp \
                                -i "$SSH_KEY" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=accept-new \
                                docker-compose.prod.yml \
                                "$SSH_USER@$DEPLOY_HOST:$DEPLOY_DIR/docker-compose.prod.yml"

                            echo "Production deployment started..."

                            ssh \
                                -i "$SSH_KEY" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=accept-new \
                                "$SSH_USER@$DEPLOY_HOST" <<EOF

set -eu

cd '$DEPLOY_DIR'

echo "Pulling latest production images..."

docker pull les190/retrodoc-backend:latest
docker pull les190/retrodoc-frontend:latest

echo "Starting PostgreSQL and Redis..."

docker compose -f docker-compose.prod.yml up -d postgres redis

echo "Waiting for infrastructure..."

sleep 10

echo "Starting backend..."

docker compose -f docker-compose.prod.yml up -d backend

echo "Waiting for backend..."

sleep 10

echo "Running Django migrations..."

docker compose -f docker-compose.prod.yml exec -T backend \
    python manage.py migrate --noinput

echo "Collecting static files..."

docker compose -f docker-compose.prod.yml exec -T backend \
    python manage.py collectstatic --noinput

echo "Running Django deployment checks..."

docker compose -f docker-compose.prod.yml exec -T backend \
    python manage.py check --deploy

echo "Starting Celery worker and frontend..."

docker compose -f docker-compose.prod.yml up -d --force-recreate celery frontend

echo "Production containers:"

docker compose -f docker-compose.prod.yml ps

echo "Checking frontend..."

curl -fsS http://127.0.0.1:3000/ >/dev/null

echo "Checking backend..."

BACKEND_STATUS=\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/ || true)

if [ "\$BACKEND_STATUS" = "000" ]; then
    echo "Backend is not reachable."

    docker compose -f docker-compose.prod.yml logs --tail=100 backend

    exit 1
fi

echo "Backend HTTP status: \$BACKEND_STATUS"

echo "RetroDoc deployment completed successfully."

EOF
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'RetroDoc DevOps pipeline completed successfully.'
        }

        failure {
            echo 'RetroDoc DevOps pipeline failed.'
        }

        always {
            echo 'RetroDoc DevOps pipeline finished.'
        }
    }
}