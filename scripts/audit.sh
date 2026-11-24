#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]  $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: проверьте, что значение параметра port отлично от 22
check "Порт SSH нестандартный" "2222" "$(sudo sshd -T | awk '/^port/{print $2}')"

# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "Максимум попыток авторизации" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
check "Политика по умолчанию (входящие)" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: ' $3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
# Проверка а) синтаксис nginx
check "Конфигурация nginx корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"

# Проверка б) срок действия сертификата (не менее 30 дней)
check "Сертификат действителен более 30 дней" "0" "$(sudo openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; echo $?)"

# Проверка в) отсутствие файлов, доступных для записи всем
check "Нет файлов, доступных для записи всем" "0" "$(find /var/www/devops-site -perm -o+w | wc -l)"

# Проверка г) права на закрытый ключ 600
check "Права на ключ 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

# [5] Контейнеризация
echo "[5] Контейнеризация"

# a) Служба docker активна
if systemctl is-active --quiet docker; then
    echo "[OK] Служба Docker активна"
else
    echo "[FAIL] Служба Docker неактивна"
fi

# б) Контейнер СУБД в состоянии healthy
DB_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo "not_found")
if [ "$DB_HEALTH" == "healthy" ]; then
    echo "[OK] Контейнер СУБД здоров"
else
    echo "[FAIL] Контейнер СУБД не здоров (статус: $DB_HEALTH)"
fi

# в) Порты 5000 и 5432 не слушаются ни на одном адресе, кроме 127.0.0.1
BAD_PORTS=$(ss -tln | grep -E ':(5000|5432)\b' | grep -v '127.0.0.1' || true)
if [ -z "$BAD_PORTS" ]; then
    echo "[OK] Порты 5000 и 5432 доступны только на 127.0.0.1"
else
    echo "[FAIL] Найдены небезопасные прослушивания портов:"
    echo "$BAD_PORTS"
fi

# г) Права файла ~/app/.env равны 600
ENV_PERMS=$(stat -c '%a' ~/app/.env 2>/dev/null || echo "missing")
if [ "$ENV_PERMS" == "600" ]; then
    echo "[OK] Права на .env (600)"
else
    echo "[FAIL] Права на .env (ожидалось: '600', получено: '$ENV_PERMS')"
fi

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

