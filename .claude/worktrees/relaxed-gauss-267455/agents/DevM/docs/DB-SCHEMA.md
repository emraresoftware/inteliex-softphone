# DB Schema — Otomatik Yazilim Uretim Platformu

## Temel Varliklar

- `users`
- `organizations`
- `memberships`
- `projects`

## Run ve Orkestrasyon

- `runs`
- `run_stages`
- `tasks`
- `agents`
- `agent_executions`

## AI ve Consensus

- `spec_versions`
- `model_requests`
- `model_responses`
- `consensus_reports`

## Hibrit Calisma (API + Computer Use)

- `execution_policies`
- `browser_runs`

## Kod / Dogrulama / Deploy

- `repo_operations`
- `validation_results`
- `deployments`

## Geri Bildirim ve Izlenebilirlik

- `feedback_items`
- `artifacts`
- `audit_logs`

## Yeni Tablolar (Hibrit Model)

### `execution_policies`

Her proje/run icin hangi gorevlerin hangi modda calisacagini belirler.

- `id`
- `project_id`
- `scope` (`project` | `run` | `task`)
- `execution_mode` (`api` | `computer_use` | `api_then_computer_use`)
- `fallback_enabled` (bool)
- `max_api_retries` (int)
- `token_budget` (numeric)
- `runtime_budget_sec` (int)
- `allowed_domains_json` (jsonb)
- `requires_human_approval` (bool)
- `created_at`
- `updated_at`

### `browser_runs`

Computer Use ile yapilan browser oturumlarinin kaydini tutar.

- `id`
- `run_id`
- `task_id`
- `provider` (`cloud_agent` vb.)
- `status` (`queued` | `running` | `success` | `failed` | `blocked`)
- `target_domain`
- `start_url`
- `steps_count` (int)
- `screenshots_ref` (text / object storage path)
- `trace_ref` (text)
- `cost_tokens_in`
- `cost_tokens_out`
- `cost_estimated_usd`
- `started_at`
- `ended_at`
- `error_message`

### Iliskiler (Ek)

- `execution_policies.project_id -> projects.id`
- `browser_runs.run_id -> runs.id`
- `browser_runs.task_id -> tasks.id`

## Notlar

- Ilk iterasyonda PostgreSQL onerilir.
- Buyuk artifact/log verisi object storage'da tutulmalidir.
- `prompt_hash` ile cache/maliyet optimizasyonu yapilabilir.
