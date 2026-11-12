#!/bin/bash
# Проверка доступности API по коду HTTP-ответа.
#
# Запуск:  ./check_api.sh URL [ТАЙМАУТ]
#   URL      адрес API, например https://httpbin.org/status/200
#   ТАЙМАУТ  сколько секунд ждать ответа (по умолчанию 5)
#
# Результат: 0 – сервер ответил 200, 1 – другой код или ошибка.

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Использование: $0 URL [ТАЙМАУТ]" >&2
    exit 1
fi

URL=$1
TIMEOUT=${2:-5}

# Адрес должен начинаться с http:// или https:// и содержать имя хоста
if ! echo "$URL" | grep -Eq '^https?://[^/[:space:]]+(/[^[:space:]]*)?$'
then
    echo "Неверный URL: $URL" >&2
    exit 1
fi

if ! [[ $TIMEOUT =~ ^[1-9][0-9]*$ ]]; then
    echo "Таймаут должен быть целым числом секунд: $TIMEOUT" >&2
    exit 1
fi

STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout "$TIMEOUT" --max-time $((TIMEOUT * 2)) "$URL")

case $STATUS in
    200)
        echo "API доступен"
        exit 0
        ;;
    *)
        echo "API недоступен, код ответа: $STATUS"
        exit 1
        ;;
esac
