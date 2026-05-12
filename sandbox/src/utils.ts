import { Database } from './database';

// TODO: add input validation
export async function processUser(userId: number): Promise<void> {
  const db = new Database();
  await db.connect('postgres://localhost:5432/myapp');

  // FIXME: handle errors properly
  const result = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  console.log(`Processed ${result.rowCount} rows`);
  await db.disconnect();
}

// Utility to export data as JSON
export function exportData(data: unknown[]): string {
  // TODO: handle circular references
  return JSON.stringify(data, null, 2);
}
