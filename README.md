# infra-monitoring-project

Учебный проект по DevOps: мониторинг доступности echo-API, разбор логов веб-сервера, запуск сервиса за nginx в Docker Compose и проверка всего этого в GitHub Actions.

## Что внутри

| Файл | Зачем |
|---|---|
| `check_api.sh` | проверяет, что API отвечает кодом 200 |
| `analyze_logs.sh` | генерирует `access.log` и считает по нему статистику |
| `docker-compose.yml` | сервисы `api` (http-echo) и `proxy` (nginx) |
| `proxy/nginx.conf` | конфиг nginx, который проксирует запросы в `api` |
| `.github/workflows/ci.yml` | проверка скриптов и стека на каждый Pull Request |

Ветки: `main` защищена, работа идет в `feature/monitoring`, в `main` все попадает через Pull Request.

## Мониторинг API

```
./check_api.sh URL [ТАЙМАУТ]
```

Скрипт отправляет запрос через `curl` и смотрит только на код ответа. Таймаут по умолчанию 5 секунд.

```
$ ./check_api.sh https://httpbin.org/status/200
API доступен
$ ./check_api.sh https://httpbin.org/status/503
API недоступен, код ответа: 503
```

Код возврата: `0`, если пришел ответ 200, и `1` во всех остальных случаях, в том числе при неверном URL и обрыве соединения (тогда код ответа `000`).

## Анализ логов

```
./analyze_logs.sh [ФАЙЛ] [СТРОК]
```

По умолчанию пишет 350 записей в `access.log` (меньше 300 нельзя) и сразу выводит:

- период, за который собран лог;
- общее количество запросов;
- топ-3 IP-адресов по числу запросов;
- сколько ответов с кодами 4xx и 5xx;
- три самых популярных адреса запросов.

Генерация сделана на `awk`, подсчет – через `grep -E`, `sort`, `uniq`, `head`, `awk` и `sed`. IP-адреса выбираются регулярным выражением `^([0-9]{1,3}\.){3}[0-9]{1,3}`.

## Docker Compose

```
docker compose up -d
curl http://localhost:80
docker compose ps
docker compose down
```

`curl` должен вернуть `Monitoring Service Active`. Контейнеры называются `echo-api` и `nginx-proxy`, оба сидят в сети `monitoring-backend` (подсеть `172.28.0.0/24`). Снаружи открыт только порт 80 у nginx, сам `api` наружу не публикуется.

Если порт 80 на машине занят, порт можно поменять:

```
PROXY_PORT=8081 docker compose up -d
```

У nginx есть служебный адрес `/nginx-health`, по нему работает healthcheck контейнера.

## CI

Workflow «Проверка проекта» запускается на каждый Pull Request:

1. `Проверка bash-скриптов` – `bash -n` для обоих скриптов, `check_api.sh https://httpbin.org/status/200` должен вернуть 0, на коде 500 и на неверном URL – 1, `analyze_logs.sh` должен создать лог не меньше чем на 300 строк.
2. `Запуск docker-compose` – стартует только после первой задачи: поднимает стек и ждет от nginx текст `Monitoring Service Active`.

## Деплой на сервер по SSH

Пример для сервера `student@192.0.2.15`, проект кладется в `~/monitoring`.

**1. Ключ.** Отдельный ключ под этот сервер:

```
ssh-keygen -t ed25519 -f ~/.ssh/monitoring_key -C "monitoring deploy"
```

**2. Копирование ключа на сервер.** Пароль спросят один раз, дальше вход по ключу:

```
ssh-copy-id -i ~/.ssh/monitoring_key.pub student@192.0.2.15
ssh -i ~/.ssh/monitoring_key student@192.0.2.15 "uname -a"
```

Чтобы не писать каждый раз `-i` и адрес, удобно завести алиас в `~/.ssh/config`:

```
Host monitoring-srv
    HostName 192.0.2.15
    User student
    IdentityFile ~/.ssh/monitoring_key
```

**3. Передача файлов.** Вариант с архивом и `scp`:

```
git archive --format=tar.gz -o /tmp/monitoring.tar.gz HEAD
scp /tmp/monitoring.tar.gz monitoring-srv:/tmp/
ssh monitoring-srv "mkdir -p ~/monitoring && tar xzf /tmp/monitoring.tar.gz -C ~/monitoring"
```

`git archive` берет только файлы из репозитория, так что логи и прочий мусор в архив не попадут.

Вариант без промежуточного файла – `tar` прямо в `ssh`:

```
tar czf - --exclude=.git --exclude='*.log' . | ssh monitoring-srv "mkdir -p ~/monitoring && tar xzf - -C ~/monitoring"
```

Если на сервере уже лежит старая версия, удобнее `rsync`, он передает только изменения:

```
rsync -az --delete --exclude .git --exclude '*.log' ./ monitoring-srv:~/monitoring/
```

**4. Запуск.**

```
ssh monitoring-srv "cd ~/monitoring && chmod +x *.sh && docker compose up -d && ./check_api.sh http://localhost"
```
