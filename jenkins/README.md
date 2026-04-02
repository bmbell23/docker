# Jenkins

Jenkins runs on port 8880 and stores state in `./jenkins_home`.

## Start

```bash
cd /home/brandon/projects/docker/jenkins
docker compose up -d --build
```

## First login password

```bash
docker logs jenkins 2>&1 | grep -A 2 "Please use the following password"
```

## Notes

- The Docker socket is mounted so Jenkins jobs can manage local containers.
- Keep deployment credentials in Jenkins Credentials, not in pipeline scripts.
