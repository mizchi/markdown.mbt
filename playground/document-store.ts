export interface SavedDocument {
  id: string;
  content: string;
  timestamp: number;
  createdAt: number;
}

// Creation order is independent of edits and selection. Break ties by stable ID.
export function compareDocuments(a: SavedDocument, b: SavedDocument): number {
  return b.createdAt - a.createdAt || a.id.localeCompare(b.id);
}

// Keep the existing database/store so the former single document is preserved.
function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('markdown-editor', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('documents');
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });
}

export async function listDocuments(): Promise<SavedDocument[]> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('documents', 'readonly');
    const documents: SavedDocument[] = [];
    const request = tx.objectStore('documents').openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      const value = cursor.value;
      documents.push({ id: String(cursor.key), content: value.content, timestamp: value.timestamp, createdAt: value.createdAt ?? value.timestamp });
      cursor.continue();
    };
    tx.oncomplete = () => { db.close(); resolve(documents.sort(compareDocuments)); };
    tx.onabort = tx.onerror = () => { db.close(); reject(tx.error); };
  });
}

export async function saveDocument(document: SavedDocument): Promise<void> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('documents', 'readwrite');

    // A successful request alone does not guarantee the transaction committed.
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onabort = tx.onerror = () => { db.close(); reject(tx.error); };
    try {
      tx.objectStore('documents').put(document, document.id);
    } catch (error) {
      tx.abort();
      db.close();
      reject(error);
    }
  });
}

export async function deleteDocument(id: string, replacement?: SavedDocument): Promise<void> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('documents', 'readwrite');
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onabort = tx.onerror = () => { db.close(); reject(tx.error); };
    try {
      const store = tx.objectStore('documents');
      store.delete(id);
      if (replacement) store.put(replacement, replacement.id);
    } catch (error) {
      tx.abort();
      db.close();
      reject(error);
    }
  });
}
