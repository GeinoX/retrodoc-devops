COMPOSE = docker compose -f docker-compose.yml -f docker-compose.dev.yml

up:
	$(COMPOSE) up --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

services-up:
	$(COMPOSE) up -d db redis

services-down:
	$(COMPOSE) stop db redis
