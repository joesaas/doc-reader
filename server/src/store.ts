import { promises as fs } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import type { DocMeta } from "../../shared/types.js";

const DATA_DIR = process.env.DATA_DIR ?? path.resolve(process.cwd(), "data");
const FILES_DIR = path.join(DATA_DIR, "files");
const INDEX_FILE = path.join(DATA_DIR, "index.json");

let docs: DocMeta[] | null = null;
let writeChain: Promise<void> = Promise.resolve();

async function ensureLoaded(): Promise<DocMeta[]> {
  if (docs) return docs;
  await fs.mkdir(FILES_DIR, { recursive: true });
  try {
    const raw = await fs.readFile(INDEX_FILE, "utf8");
    const parsed = JSON.parse(raw);
    docs = Array.isArray(parsed) ? (parsed as DocMeta[]) : [];
  } catch {
    docs = [];
  }
  return docs;
}

function persist(): Promise<void> {
  // 串行化落盘 + 临时文件rename，保证 index.json 不会写一半
  writeChain = writeChain.then(async () => {
    const tmp = INDEX_FILE + ".tmp";
    await fs.writeFile(tmp, JSON.stringify(docs ?? [], null, 2), "utf8");
    await fs.rename(tmp, INDEX_FILE);
  });
  return writeChain;
}

export async function listDocs(): Promise<DocMeta[]> {
  const all = await ensureLoaded();
  return [...all].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export async function getDoc(id: string): Promise<DocMeta | undefined> {
  const all = await ensureLoaded();
  return all.find((d) => d.id === id);
}

export function docFilePath(doc: DocMeta): string {
  return path.join(FILES_DIR, doc.fileName);
}

export async function addDoc(
  meta: Omit<DocMeta, "id" | "fileName" | "createdAt" | "updatedAt">,
  html: string,
): Promise<DocMeta> {
  const all = await ensureLoaded();
  const id = randomUUID().slice(0, 12);
  const now = new Date().toISOString();
  const doc: DocMeta = {
    ...meta,
    id,
    fileName: `${id}.html`,
    createdAt: now,
    updatedAt: now,
  };
  await fs.writeFile(docFilePath(doc), html, "utf8");
  all.push(doc);
  await persist();
  return doc;
}

export async function updateDoc(
  id: string,
  patch: Partial<Pick<DocMeta, "title" | "description" | "category" | "tags">>,
): Promise<DocMeta | undefined> {
  const all = await ensureLoaded();
  const doc = all.find((d) => d.id === id);
  if (!doc) return undefined;
  Object.assign(doc, patch, { updatedAt: new Date().toISOString() });
  await persist();
  return doc;
}

export async function removeDoc(id: string): Promise<boolean> {
  const all = await ensureLoaded();
  const idx = all.findIndex((d) => d.id === id);
  if (idx < 0) return false;
  const [doc] = all.splice(idx, 1);
  await fs.rm(docFilePath(doc), { force: true });
  await persist();
  return true;
}

/** 导入脚本用：同名文件已导入过就跳过 */
export async function findByOriginalName(name: string): Promise<DocMeta | undefined> {
  const all = await ensureLoaded();
  return all.find((d) => d.originalName === name);
}

export { DATA_DIR, FILES_DIR };
