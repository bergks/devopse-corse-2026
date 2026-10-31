#!/usr/bin/env bash

# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

# --- Переменные ---
REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"
DRY_RUN=false

# --- 1. Разбор аргумента --dry-run ---
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
elif [[ -n "${1:-}" ]]; then
    echo "Ошибка: Неизвестный аргумент '$1'. Использование: $0 [--dry-run]" >&2
    exit 1
fi

# --- 2. Проверки по требованиям 4 и 5 ---

# Проверка 4: Если файл site/index.html отсутствует, доставка не выполняется
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: Файл ${LOCAL_DIR}index.html не найден. Доставка отменена." >&2
    exit 1
fi

# Проверка 5: Если в репозитории есть незафиксированные изменения
if ! git diff-index --quiet HEAD --; then
    echo "Ошибка: В репозитории есть незафиксированные изменения. Сделайте commit." >&2
    exit 1
fi

# --- 3. Синхронизация каталога ---
# Формируем флаги для rsync
RSYNC_FLAGS="-avz --delete --chmod=D755,F644"
if [[ "${DRY_RUN}" == "true" ]]; then
    RSYNC_FLAGS="${RSYNC_FLAGS} --dry-run"
    echo "=== РЕЖИМ ПРОСМОТРА (DRY-RUN) ==="
fi

# Требование 8 и 9: Не более одного SSH-соединения и без интерактивного пароля
# Используем BatchMode=yes, чтобы SSH не спрашивал пароль, если ключ не подходит
echo "Синхронизация ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}..."
rsync ${RSYNC_FLAGS} -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# --- 4. При --dry-run — завершение с кодом 0 ---
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "=== ПРОСМОТР ЗАВЕРШЕН. Изменения не внесены. ==="
    exit 0
fi

# --- 5. Проверка доступности сайта ---
echo "Проверка доступности ${SITE_URL}..."
# curl -f (fail) возвращает ненулевой код при ошибках 4xx/5xx
if ! curl -s -f --cacert "${CA_CERT}" "${SITE_URL}" > /dev/null; then
    echo "Ошибка: Сайт ${SITE_URL} недоступен после деплоя!" >&2
    exit 1
fi

# Требование 7: Успешное завершение с выводом короткого хеша коммита
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "Успех! Доставлен коммит: ${COMMIT_HASH}"
exit 0
