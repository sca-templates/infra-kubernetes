# Project: Implement Redis

Area: Data · Wave 40 · Environments: local→dev→qa→prod
Depends on: redis-operator (#12) — operator must be present.
Project done when: `RedisReplication` CR honored; Redis pods `Running` (with Sentinel in qa/prod); `PING`/`SET` works;
password auth configured per env.

No natural phases → issues directly under the project.

- [x] Issue #17 · `RedisReplication` CR + auth
  Depends on: redis-operator (#12)
  - [x] `infrastructure/redis/manifests/` `RedisReplication` CR for 4 envs
        - [x] local/dev: 1 replica; qa/prod: 3 replicas
        - Commits: `feat(redis): redis CR`
  - [x] auth via secret (`secret/redis/<env>` projected by ESO → `redis-password`)
        Commits: `feat(redis): password auth`
  - [x] smoke: `redis-cli PING` → PONG; `SET`/`GET` roundtrip + AOF verification; Sentinel checked in qa/prod
        Commits: `test(redis): ping and get/set smoke`
  - [x] docs: Work Log row + catalog Status → deployed
        Commits: `docs(redis): mark deployed`
  Issue done when: Redis pod `Running` + PING/auth roundtrip ok.
