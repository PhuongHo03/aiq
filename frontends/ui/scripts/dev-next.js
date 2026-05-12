const { spawn } = require('child_process')

const port = process.env.NEXT_DEV_PORT || '3001'
const nextCli = require.resolve('next/dist/bin/next')
const child = spawn(process.execPath, [nextCli, 'dev', '--turbopack', '-p', port], {
  stdio: 'inherit',
  shell: false,
})

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal)
    return
  }
  process.exit(code || 0)
})
