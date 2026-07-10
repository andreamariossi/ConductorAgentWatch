import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const logPath = path.join(os.homedir(), '.conductoragentwatch', 'app.log');

function writeLog(level: string, message: string, error?: unknown) {
  const timestamp = new Date().toISOString();
  let logLine = `[${timestamp}] [${level}] ${message}`;
  if (error !== undefined) {
    if (error instanceof Error) {
      logLine += `\n  Error: ${error.message}\n  Stack: ${error.stack}`;
    } else {
      logLine += `\n  Error: ${JSON.stringify(error)}`;
    }
  }
  logLine += '\n';

  console.log(logLine.trim());

  try {
    const dir = path.dirname(logPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.appendFileSync(logPath, logLine, 'utf8');
  } catch (err) {
    console.error('Failed to write log file:', err);
  }
}

export const Logger = {
  info(message: string) {
    writeLog('INFO', message);
  },
  warn(message: string) {
    writeLog('WARN', message);
  },
  error(message: string, error?: unknown) {
    writeLog('ERROR', message, error);
  },
};
