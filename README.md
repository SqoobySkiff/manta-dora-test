# M.A.N.T.A. DORA Test Repository (`manta-dora-test`)

Тестовий репозиторій для повної перевірки GitHub-інтеграції, DORA-метрик, Health Sources (MTTR), Dead Letters Queue (DLQ) та ізоляції середовищ (`production` vs `staging`) у платформі **M.A.N.T.A.**

## Структура репозиторію

- `.github/workflows/test-deployment.yml` — workflow **Test production deployment event** (`workflow_dispatch`), який створює GitHub Deployment + Deployment Status без реального деплою коду. Підтримує:
  - `environment`: `production` (враховується в DORA) або `staging` (має ігноруватися M.A.N.T.A.).
  - `outcome`:
    - `success` — успішний деплой (Deployment Frequency + Lead Time for Changes);
    - `failure` — невдалий деплой (Change Failure Rate);
    - `rollback` — відкочений деплой (`state: inactive` + ключове слово `rollback` для Change Failure Rate).
- `docs/test-log.md` — файл для безпечних тестових коммітів у feature-гілках / PR.
- `scripts/manta-test-helpers.ps1` — PowerShell-помічник для:
  - створення feature-гілки і 1-го / 2-го комміту для тесту Lead Time;
  - відправки `FAIL` / `PASS` health-сигналів (MTTR);
  - відправки poison-вебхука для перевірки Dead Letters Queue (`/dead-letters`);
  - перевірки стану таблиць PostgreSQL.

## Швидкий старт

1. Створи порожній репозиторій на GitHub (наприклад, `SqoobySkiff/manta-dora-test`) **без** README / `.gitignore` / License.
2. Прив'яжи remote і запуш `main`:
   ```powershell
   git remote add origin https://github.com/SqoobySkiff/manta-dora-test.git
   git push -u origin main
   ```
3. Підключи GitHub у M.A.N.T.A., створи проєкт, прив'яжи репозиторій, запусти `cloudflared tunnel --url http://localhost:8000` і налаштуй Webhook у GitHub (`Pushes`, `Pull requests`, `Deployments`, `Deployment statuses`).
4. Тільки **після** налаштування вебхука створюй тестові гілки/PR і запускай workflow **Test production deployment event**.
