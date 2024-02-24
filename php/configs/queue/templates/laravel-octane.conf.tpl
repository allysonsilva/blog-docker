[program:laravel-octane]
process_name=%(program_name)s
command=php -d variables_order=EGPCS artisan octane:frankenphp --host=0.0.0.0 --admin-port=2019 --port=8000 --env=%(ENV_APP_ENV)s
directory=%(ENV_REMOTE_SRC)s
user=%(ENV_USER_NAME)s
autostart=true
autorestart=true
priority=2
environment=LARAVEL_OCTANE="1"

stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

; (30 seconds) timeout to give jobs time to finish
; Graceful shutdown
stopwaitsecs=30
