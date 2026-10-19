import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export type ChangelogBlock =
  | { type: 'paragraph'; text: string }
  | { type: 'list'; items: string[] };

export interface ChangelogEntry {
  version: string;
  date: string;
  anchor: string;
  blocks: ChangelogBlock[];
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

export function inlineMarkdown(value: string): string {
  let output = escapeHtml(value);
  output = output.replace(/`([^`]+)`/g, '<code>$1</code>');
  output = output.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  output = output.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  return output;
}

function anchorFor(version: string): string {
  return 'v' + version.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function renderBody(lines: string[]): ChangelogBlock[] {
  const blocks: ChangelogBlock[] = [];
  let paragraph: string[] = [];
  let items: string[] = [];

  const flushParagraph = () => {
    if (paragraph.length > 0) {
      blocks.push({ type: 'paragraph', text: paragraph.join(' ') });
      paragraph = [];
    }
  };

  const flushList = () => {
    if (items.length > 0) {
      blocks.push({ type: 'list', items });
      items = [];
    }
  };

  for (const raw of lines) {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      flushParagraph();
      flushList();
    } else if (trimmed.startsWith('- ')) {
      flushParagraph();
      items.push(trimmed.slice(2));
    } else if (items.length > 0 && /^\s/.test(raw)) {
      items[items.length - 1] += ' ' + trimmed;
    } else {
      flushList();
      paragraph.push(trimmed);
    }
  }
  flushParagraph();
  flushList();
  return blocks;
}

export function getChangelogEntries(): ChangelogEntry[] {
  const candidates = [
    resolve(process.cwd(), '../CHANGELOG.md'),
    resolve(process.cwd(), 'CHANGELOG.md'),
  ];
  const path = candidates.find((candidate) => existsSync(candidate));
  if (!path) {
    throw new Error(`CHANGELOG.md not found from ${process.cwd()}`);
  }

  const entries: ChangelogEntry[] = [];
  let current: { version: string; date: string; body: string[] } | null = null;

  const finish = () => {
    if (!current) return;
    while (current.body.length > 0 && current.body[0].trim() === '') current.body.shift();
    while (current.body.length > 0 && current.body[current.body.length - 1].trim() === '') {
      current.body.pop();
    }
    if (current.version.length > 0 && current.body.length > 0) {
      entries.push({
        version: current.version,
        date: current.date,
        anchor: anchorFor(current.version),
        blocks: renderBody(current.body),
      });
    }
    current = null;
  };

  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (line.startsWith('## ')) {
      finish();
      const title = line.slice(3).trim();
      if (title.toLowerCase().startsWith('unreleased')) continue;
      const separator = title.includes(' — ') ? ' — ' : title.includes(' - ') ? ' - ' : null;
      const [version, date] = separator
        ? [title.slice(0, title.indexOf(separator)).trim(), title.slice(title.indexOf(separator) + separator.length).trim()]
        : [title, ''];
      current = { version, date, body: [] };
    } else if (line.startsWith('# ')) {
      continue;
    } else if (current) {
      current.body.push(line);
    }
  }
  finish();
  return entries;
}
