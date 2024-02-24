[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php artisan queue:work {{QUEUE_CONNECTION}} --max-time=3600 --max-jobs=500 --queue=important,high,broadcast,{{REDIS_QUEUE}},low --memory={{QUEUE_MEMORY}} --env=%(ENV_APP_ENV)s --sleep={{QUEUE_SLEEP}} --tries={{QUEUE_TRIES}} --backoff={{QUEUE_BACKOFF}} --timeout={{QUEUE_TIMEOUT}}
directory=%(ENV_REMOTE_SRC)s
user=%(ENV_USER_NAME)s
autostart=true
autorestart=true
numprocs=6
startretries=2

stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

; (300 seconds) timeout to give jobs time to finish
; Graceful shutdown
stopasgroup=true
killasgroup=true
stopsignal=TERM
stopwaitsecs=300
