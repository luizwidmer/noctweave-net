import {
  LabPublisherIdentity,
  createPublisherIdentity,
} from "./lab-v0";

const DATABASE_NAME = "noctweb-lab-vault";
const STORE_NAME = "publisher-identities";
const IDENTITY_KEY = "quiet-garden";

type StoredIdentity = LabPublisherIdentity & { id: typeof IDENTITY_KEY };

function openVault(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, 1);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(STORE_NAME)) {
        request.result.createObjectStore(STORE_NAME, { keyPath: "id" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () =>
      reject(request.error ?? new Error("Unable to open the publisher key vault."));
  });
}

function readIdentity(database: IDBDatabase): Promise<StoredIdentity | null> {
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).get(IDENTITY_KEY);
    request.onsuccess = () =>
      resolve((request.result as StoredIdentity | undefined) ?? null);
    request.onerror = () =>
      reject(request.error ?? new Error("Unable to read the publisher identity."));
  });
}

function storeIdentity(
  database: IDBDatabase,
  identity: LabPublisherIdentity,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    transaction.objectStore(STORE_NAME).put({
      id: IDENTITY_KEY,
      ...identity,
    } satisfies StoredIdentity);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () =>
      reject(
        transaction.error ?? new Error("Unable to store the publisher identity."),
      );
  });
}

export async function loadOrCreatePublisherIdentity(): Promise<LabPublisherIdentity> {
  if (typeof indexedDB === "undefined") {
    return createPublisherIdentity();
  }

  const database = await openVault();
  try {
    const stored = await readIdentity(database);
    if (
      stored?.publisherID &&
      stored.publicKeyBytes &&
      stored.publicKey &&
      stored.privateKey &&
      stored.algorithm === "Ed25519-lab"
    ) {
      return {
        algorithm: stored.algorithm,
        publisherID: stored.publisherID,
        publicKeyBytes: stored.publicKeyBytes,
        publicKey: stored.publicKey,
        privateKey: stored.privateKey,
      };
    }

    const identity = await createPublisherIdentity();
    await storeIdentity(database, identity);
    return identity;
  } finally {
    database.close();
  }
}
