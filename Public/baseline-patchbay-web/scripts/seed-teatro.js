#!/usr/bin/env node
import { spawn } from 'node:child_process'

const run = (cmd, args, opts = {}) => new Promise((resolve, reject) => {
  const p = spawn(cmd, args, { stdio: 'inherit', ...opts })
  p.on('exit', (code) => code === 0 ? resolve(undefined) : reject(new Error(`${cmd} exited ${code}`)))
})

;(async () => {
  try {
    console.log('[seed] Running grid-dev-seed…')
    await run('swift', ['run', '--package-path', 'Packages/FountainApps', 'grid-dev-seed'], { cwd: process.cwd() + '/..' })
  } catch (e) {
    console.warn('[seed] grid-dev-seed failed or unavailable:', e.message)
  }
  try {
    console.log('[seed] Running baseline-robot-seed…')
    await run('swift', ['run', '--package-path', 'Packages/FountainApps', 'baseline-robot-seed'], { cwd: process.cwd() + '/..' })
  } catch (e) {
    console.warn('[seed] baseline-robot-seed failed or unavailable:', e.message)
  }
  try {
  } catch (e) {
    // ignore optional extra seeders
  }
  try {
    console.log('[seed] Dumping MRTS facts…')
    await run('swift', ['run', '--package-path', 'Packages/FountainApps', 'store-dump'], { cwd: process.cwd() + '/..' })
  } catch (e) {
    console.warn('[seed] store-dump failed:', e.message)
  }
  console.log('[seed] Done.')
})()
