#!/bin/bash
# Генерация тестового access.log и анализ запросов в нем.
#
# Запуск:  ./analyze_logs.sh [ФАЙЛ] [СТРОК]
#   ФАЙЛ   куда записать лог (по умолчанию access.log)
#   СТРОК  сколько записей сгенерировать (по умолчанию 350, минимум 300)

set -u

LOG=${1:-access.log}
COUNT=${2:-350}

# IP-адрес в начале строки: четыре группы по 1-3 цифры через точку
IP_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}'

if [ "$#" -gt 2 ]; then
    echo "Использование: $0 [ФАЙЛ] [СТРОК]" >&2
    exit 1
fi

if ! [[ $COUNT =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 300 ]; then
    echo "Число строк должно быть целым и не меньше 300: $COUNT" >&2
    exit 1
fi

# Записи генерирует awk. Повторы в списках делают одни IP и коды
# частыми, а другие редкими. srand с постоянным числом дает один
# и тот же лог при каждом запуске.
generate_log() {
    awk -v count="$COUNT" 'BEGIN {
        srand(2608)
        n_ip = split("192.168.0.21 192.168.0.21 192.168.0.21" \
            " 192.168.0.21 10.10.1.4 10.10.1.4 10.10.1.4" \
            " 172.20.5.17 172.20.5.17 192.168.0.34 192.168.0.34" \
            " 10.10.1.9 198.51.100.23 203.0.113.50", ip, " ")
        n_req = split("GET /api/products|GET /api/products" \
            "|GET /api/products/15|GET /api/cart|POST /api/cart" \
            "|POST /api/auth/login|PUT /api/profile" \
            "|DELETE /api/cart/3|GET /metrics", req, "|")
        n_code = split("200 200 200 200 200 200 200 200 200 200" \
            " 201 204 302 400 401 403 404 404 500 502 504", code, " ")

        t = 9 * 3600
        for (i = 0; i < count; i++) {
            printf "%s - - [16/Aug/2026:%02d:%02d:%02d] \"%s HTTP/1.1\" %s\n",
                ip[int(rand() * n_ip) + 1],
                int(t / 3600) % 24, int(t / 60) % 60, t % 60,
                req[int(rand() * n_req) + 1],
                code[int(rand() * n_code) + 1]
            t += int(rand() * 5)
        }
    }'
}

separator() {
    printf '%.0s-' {1..46}
    echo
}

analyze_log() {
    local total first last client server

    total=$(grep -cE "$IP_REGEX" "$LOG")
    first=$(head -n 1 "$LOG" | sed -E 's/.*\[([^]]+)\].*/\1/')
    last=$(tail -n 1 "$LOG" | sed -E 's/.*\[([^]]+)\].*/\1/')
    client=$(grep -cE '" 4[0-9]{2}$' "$LOG")
    server=$(grep -cE '" 5[0-9]{2}$' "$LOG")

    echo "Файл: $LOG"
    echo "Период: $first – $last"
    separator
    echo "Всего запросов: $total"
    echo
    echo "Топ-3 IP-адресов:"
    grep -oE "$IP_REGEX" "$LOG" | sort | uniq -c | sort -rn | head -n 3 |
        awk '{ printf "  %d) %-15s – %d\n", NR, $2, $1 }'
    echo
    echo "Коды ответов 4xx: $client"
    echo "Коды ответов 5xx: $server"
    echo
    echo "Популярные адреса запросов:"
    awk '{ print $6 }' "$LOG" | sort | uniq -c | sort -rn | head -n 3 |
        awk '{ printf "  %-22s – %d\n", $2, $1 }'
    separator
}

if ! generate_log > "$LOG"; then
    echo "Не удалось записать файл $LOG" >&2
    exit 1
fi

analyze_log
