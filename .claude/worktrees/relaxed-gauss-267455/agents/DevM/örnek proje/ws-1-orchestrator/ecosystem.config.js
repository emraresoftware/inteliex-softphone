module.exports = {
  apps: [{
    name: 'talimatlar-watch',
    script: 'scripts/watch-talimatlar.js',
    cwd: __dirname,
    exec_mode: 'fork',
    instances: 1,
    autorestart: true,
    watch: false,
    max_restarts: 10,
    env: {
      NODE_ENV: 'production'
    }
  }]
};
