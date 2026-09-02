# Project: Implement Redis

Area: Data · Wave 40 · Environments: local→dev→qa→prod
Depends on: redis-operator (#7) — operator must be present.
Project done when: `Redis` CR honored; Redis pod `Running`; `PING`/`SET` works;
SCRAM or password auth configured per env.

No natural phases → issues directly under the project.

- [ ] Issue #12 · `Redis` CR + auth
  Depends on: redis-operator (#7)
  - [ ] `infrastructure/redis/` `Redis` CR for 4 envs
        - [ ] local/dev: 1 master; qa/prod: 3 replicas
        - Commits: `feat(redis): redis CR`
  - [ ] auth via secret (password from `.secrets/`, never git)
        Commits: `feat(redis): password auth`
  - [ ] smoke: `redis-cli PING` → PONG; `SET`/`GET` roundtrip
        Commits: `test(redis): ping and get/set smoke`
  - [ ] docs: Work Log row + catalog Status → deployed
        Commits: `docs(redis): mark deployed`
  Issue done when: Redis pod `Running` + PING/auth roundtrip ok.
