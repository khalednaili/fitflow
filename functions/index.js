const admin = require('firebase-admin');
const functions = require('firebase-functions');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onObjectFinalized, onObjectDeleted } = require('firebase-functions/v2/storage');

admin.initializeApp();

// ---------------------------------------------------------------------------
// Helper: verify the caller has a given role
// ---------------------------------------------------------------------------
async function assertRole(context, ...allowedRoles) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }
  const actorDoc = await admin.firestore().collection('users').doc(context.auth.uid).get();
  const actorRole = actorDoc.exists ? actorDoc.data().role : null;
  if (!allowedRoles.includes(actorRole)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      `Role '${actorRole}' is not allowed. Required: ${allowedRoles.join(', ')}.`,
    );
  }
  return actorRole;
}

// ---------------------------------------------------------------------------
// bootstrapSuperAdmin — one-time setup of the FIRST super admin.
// Succeeds only when zero super_admin users exist in the system.
// The caller must already be a signed-in Firebase Auth user.
// ---------------------------------------------------------------------------
exports.bootstrapSuperAdmin = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  // Block if any super_admin already exists
  const existing = await admin.firestore()
    .collection('users')
    .where('role', '==', 'super_admin')
    .limit(1)
    .get();

  if (!existing.empty) {
    throw new functions.https.HttpsError(
      'already-exists',
      'A super admin already exists. Use the super admin panel to create more.',
    );
  }

  const uid = context.auth.uid;

  // Promote the calling user to super_admin
  await admin.firestore().collection('users').doc(uid).set(
    {
      role: 'super_admin',
      roles: ['super_admin'],
      gymId: '',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  await admin.firestore().collection('config').doc('app').set(
    {
      bootstrapped: true,
      bootstrappedAt: admin.firestore.FieldValue.serverTimestamp(),
      bootstrappedBy: uid,
    },
    {merge: true},
  );

  return {success: true, uid};
});

// ---------------------------------------------------------------------------
// adminSetUserPassword — admin or super_admin can reset a member's password
// ---------------------------------------------------------------------------
exports.adminSetUserPassword = functions.https.onCall(async (data, context) => {
  await assertRole(context, 'admin', 'super_admin');

  const userId = typeof data.userId === 'string' ? data.userId.trim() : '';
  const newPassword = typeof data.newPassword === 'string' ? data.newPassword.trim() : '';

  if (!userId) {
    throw new functions.https.HttpsError('invalid-argument', 'userId is required.');
  }
  if (newPassword.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
  }

  await admin.auth().updateUser(userId, {password: newPassword});
  await admin.firestore().collection('users').doc(userId).set(
    {updatedAt: admin.firestore.FieldValue.serverTimestamp()},
    {merge: true},
  );

  return {success: true};
});

// ---------------------------------------------------------------------------
// superAdminCreateGym — creates gym document + Firebase Auth admin user
// ---------------------------------------------------------------------------
exports.superAdminCreateGym = functions.https.onCall(async (data, context) => {
  await assertRole(context, 'super_admin');

  const gymName = (data.gymName || '').trim();
  const gymAddress = (data.gymAddress || '').trim();
  const gymDescription = (data.gymDescription || '').trim();
  const gymLatitude = typeof data.gymLatitude === 'number' ? data.gymLatitude : null;
  const gymLongitude = typeof data.gymLongitude === 'number' ? data.gymLongitude : null;
  const adminEmail = (data.adminEmail || '').trim();
  const adminPassword = (data.adminPassword || '').trim();
  const adminName = (data.adminName || '').trim();

  if (!gymName) throw new functions.https.HttpsError('invalid-argument', 'gymName is required.');
  if (!adminEmail) throw new functions.https.HttpsError('invalid-argument', 'adminEmail is required.');
  if (adminPassword.length < 6) throw new functions.https.HttpsError('invalid-argument', 'adminPassword must be at least 6 characters.');

  // Create the Firebase Auth user for the admin
  let adminUid;
  try {
    const userRecord = await admin.auth().createUser({
      email: adminEmail,
      password: adminPassword,
      displayName: adminName,
    });
    adminUid = userRecord.uid;
  } catch (err) {
    if (err.code === 'auth/email-already-exists') {
      throw new functions.https.HttpsError(
        'already-exists',
        `The email "${adminEmail}" is already in use by another account.`,
      );
    }
    throw new functions.https.HttpsError('internal', `Failed to create admin account: ${err.message}`);
  }

  // Create gym + user Firestore documents in a single batch.
  // If this fails, roll back the Auth account so no orphan is left.
  try {
    const gymRef = admin.firestore().collection('gyms').doc();
    const gymId = gymRef.id;

    const batch = admin.firestore().batch();

    batch.set(gymRef, {
      name: gymName,
      address: gymAddress,
      description: gymDescription,
      logoUrl: '',
      ...(gymLatitude !== null ? { latitude: gymLatitude } : {}),
      ...(gymLongitude !== null ? { longitude: gymLongitude } : {}),
      adminUid,
      adminEmail,
      status: 'active',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: context.auth.uid,
    });

    batch.set(admin.firestore().collection('users').doc(adminUid), {
      email: adminEmail,
      displayName: adminName,
      role: 'admin',
      roles: ['admin'],
      gymId,
      membershipPlanId: '',
      subscriptionStatus: 'none',
      phoneNumber: '',
      photoUrl: '',
      gender: '',
      dateOfBirth: null,
      fitnessLevel: '',
      emergencyContactName: '',
      emergencyContactPhone: '',
      healthNotes: '',
      joinDate: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return {success: true, gymId, adminUid};
  } catch (err) {
    // Roll back: delete the Auth account so no orphaned user is left.
    try { await admin.auth().deleteUser(adminUid); } catch (_) {}
    throw new functions.https.HttpsError('internal', `Failed to save gym data: ${err.message}`);
  }
});

// ---------------------------------------------------------------------------
// superAdminCreateSuperAdmin — creates another super admin account
// ---------------------------------------------------------------------------
exports.superAdminCreateSuperAdmin = functions.https.onCall(async (data, context) => {
  await assertRole(context, 'super_admin');

  const email = (data.email || '').trim();
  const password = (data.password || '').trim();
  const displayName = (data.displayName || '').trim();

  if (!email) throw new functions.https.HttpsError('invalid-argument', 'email is required.');
  if (password.length < 6) throw new functions.https.HttpsError('invalid-argument', 'password must be at least 6 characters.');

  const userRecord = await admin.auth().createUser({email, password, displayName});
  const uid = userRecord.uid;

  await admin.firestore().collection('users').doc(uid).set({
    email,
    displayName,
    role: 'super_admin',
    roles: ['super_admin'],
    gymId: '',
    membershipPlanId: '',
    subscriptionStatus: 'none',
    phoneNumber: '',
    photoUrl: '',
    gender: '',
    dateOfBirth: null,
    fitnessLevel: '',
    emergencyContactName: '',
    emergencyContactPhone: '',
    healthNotes: '',
    joinDate: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {success: true, uid};
});

// ---------------------------------------------------------------------------
// superAdminToggleGymStatus — activate or suspend a gym
// ---------------------------------------------------------------------------
exports.superAdminToggleGymStatus = functions.https.onCall(async (data, context) => {
  await assertRole(context, 'super_admin');

  const gymId = (data.gymId || '').trim();
  const status = (data.status || '').trim();

  if (!gymId) throw new functions.https.HttpsError('invalid-argument', 'gymId is required.');
  if (!['active', 'suspended'].includes(status)) {
    throw new functions.https.HttpsError('invalid-argument', "status must be 'active' or 'suspended'.");
  }

  await admin.firestore().collection('gyms').doc(gymId).update({
    status,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {success: true};
});

// ---------------------------------------------------------------------------
// superAdminDeleteGym — permanently delete a gym and ALL related data
// Deletes every Firestore document scoped to the gym, then removes all
// Firebase Auth accounts that belonged to that gym (members + admin).
// ---------------------------------------------------------------------------
exports.superAdminDeleteGym = functions.https.onCall(
  {timeoutSeconds: 540, memory: '512MB'},
  async (data, context) => {
    await assertRole(context, 'super_admin');

    const gymId = (data.gymId || '').trim();
    if (!gymId) {
      throw new functions.https.HttpsError('invalid-argument', 'gymId is required.');
    }

    const db = admin.firestore();

    // Verify the gym exists before doing anything destructive.
    const gymDoc = await db.collection('gyms').doc(gymId).get();
    if (!gymDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Gym not found.');
    }

    // Helper: drain a query and delete all matching documents in 500-doc batches.
    async function deleteByGymId(collectionName) {
      let total = 0;
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const snap = await db.collection(collectionName)
          .where('gymId', '==', gymId)
          .limit(500)
          .get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
        total += snap.size;
        if (snap.size < 500) break;
      }
      return total;
    }

    const summary = {};

    // --- Firestore collections scoped to this gym ---
    const gymCollections = [
      'classes',
      'bookings',
      'waitlists',
      'attendance',
      'membership_plans',
      'subscriptions',
      'user_subscriptions',
      'classTypes',
      'classTemplates',
      'wods',
      'wodScores',
      'personal_trainings',
      'late_cancellations',
      'notifications',
      'settings',
    ];

    for (const col of gymCollections) {
      summary[col] = await deleteByGymId(col);
    }

    // --- Users: collect UIDs, delete Auth accounts, then Firestore docs ---
    const allUids = [];
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const snap = await db.collection('users')
        .where('gymId', '==', gymId)
        .limit(500)
        .get();
      if (snap.empty) break;

      const uids = snap.docs.map(doc => doc.id);
      allUids.push(...uids);

      // Delete Firestore user docs
      const batch = db.batch();
      snap.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();

      if (snap.size < 500) break;
    }

    // Delete Firebase Auth accounts in batches of 1000 (deleteUsers limit)
    for (let i = 0; i < allUids.length; i += 1000) {
      await admin.auth().deleteUsers(allUids.slice(i, i + 1000));
    }
    summary['users'] = allUids.length;

    // --- Finally, delete the gym document itself ---
    await db.collection('gyms').doc(gymId).delete();

    return {success: true, gymId, summary};
  });


// ---------------------------------------------------------------------------
// sendAnnouncementNotification — fan-out a push notification to all active
// members of a gym. Called by admin when publishing an announcement.
// ---------------------------------------------------------------------------
exports.sendAnnouncementNotification = functions.https.onCall(async (data, context) => {
  await assertRole(context, 'admin', 'super_admin');

  const gymId = (data.gymId || '').trim();
  const title = (data.title || '').trim();
  const body = (data.body || '').trim();

  if (!gymId) throw new functions.https.HttpsError('invalid-argument', 'gymId is required.');
  if (!title) throw new functions.https.HttpsError('invalid-argument', 'title is required.');
  if (!body) throw new functions.https.HttpsError('invalid-argument', 'body is required.');

  const db = admin.firestore();
  const messaging = admin.messaging();

  // Collect all FCM tokens for members of this gym.
  const usersSnap = await db.collection('users')
    .where('gymId', '==', gymId)
    .get();

  const tokens = [];
  for (const doc of usersSnap.docs) {
    const fcmTokens = doc.data().fcmTokens;
    if (Array.isArray(fcmTokens)) tokens.push(...fcmTokens);
  }

  if (tokens.length === 0) {
    return {success: true, sent: 0, message: 'No registered devices found.'};
  }

  // FCM multicast is capped at 500 tokens per request.
  let sent = 0;
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: chunk,
      notification: {title, body},
      webpush: {
        notification: {
          title,
          body,
          icon: '/icons/Icon-192.png',
        },
      },
    });
    sent += response.successCount;
  }

  return {success: true, sent, total: tokens.length};
});

// Skips documents that already have a gymId set.
// Skips super_admin user docs.
// Call once as super_admin, then this function will be removed.
// ---------------------------------------------------------------------------
exports.migrateAllToGym = functions.https.onCall(
  {timeoutSeconds: 540, memory: '512MB'},
  async (data, context) => {
    await assertRole(context, 'super_admin');
    const { gymId } = data;
    if (!gymId) throw new functions.https.HttpsError('invalid-argument', 'gymId required');

    const db = admin.firestore();

    // Collections to migrate (every model that has a gymId field)
    const collections = [
      'classes',
      'classTypes',
      'classTemplates',
      'bookings',
      'waitlists',
      'attendance',
      'membership_plans',
      'subscriptions',
      'user_subscriptions',
      'wods',
      'wodScores',
      'personal_trainings',
      'late_cancellations',
      'notifications',
      'settings',
    ];

    const summary = {};

    // Helper: commit in batches of 500 (Firestore limit)
    async function commitBatches(refs) {
      let count = 0;
      while (refs.length > 0) {
        const chunk = refs.splice(0, 500);
        const batch = db.batch();
        chunk.forEach(ref => batch.update(ref, { gymId }));
        await batch.commit();
        count += chunk.length;
      }
      return count;
    }

    // Migrate each plain collection
    for (const col of collections) {
      const snap = await db.collection(col).get();
      const refs = snap.docs
        .filter(doc => !doc.data().gymId || doc.data().gymId === '')
        .map(doc => doc.ref);
      summary[col] = await commitBatches(refs);
    }

    // Users: skip super_admins
    const usersSnap = await db.collection('users').get();
    const userRefs = usersSnap.docs
      .filter(doc => {
        const d = doc.data();
        return d.role !== 'super_admin' && (!d.gymId || d.gymId === '');
      })
      .map(doc => doc.ref);
    summary['users'] = await commitBatches(userRefs);

    return { gymId, summary };
  });

// ---------------------------------------------------------------------------
// Per-gym usage metering — powers the super admin "Gym Usage & Billing"
// screen, which estimates each gym's Firebase footprint and lets the super
// admin issue a platform invoice to that gym.
//
// One onDocumentWritten trigger per gym-scoped collection below increments
// cumulative counters on `gymUsage/{gymId}` so usage can be read cheaply
// without re-querying every collection. Reads are NOT tracked (there is no
// server-side Firestore "read" trigger); only writes, deletes, and estimated
// document storage size are metered.
// ---------------------------------------------------------------------------
const GYM_SCOPED_COLLECTIONS = [
  'absences', 'announcements', 'attendance', 'bookings', 'classReviews',
  'classTemplates', 'classTypes', 'classes', 'coach_unavailability',
  'dropInRefunds', 'invoices', 'late_cancellations', 'membership_plans',
  'notifications', 'personal_trainings', 'product_orders', 'products',
  'sales', 'settings', 'subscriptions', 'user_subscriptions', 'users',
  'waitlists', 'wodScores', 'wods',
];

/// Rough estimate of a document's on-disk size — good enough to compare gyms
/// relatively, not an exact match of Firestore's internal billing formula.
function estimateDocBytes(data) {
  if (!data) return 0;
  try {
    return Buffer.byteLength(JSON.stringify(data), 'utf8');
  } catch (_) {
    return 0;
  }
}

async function recordGymUsage(collectionName, event) {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  const gymId = (after && after.gymId) || (before && before.gymId);
  if (!gymId) return null;

  const beforeBytes = estimateDocBytes(before);
  const afterBytes = estimateDocBytes(after);
  const byteDelta = afterBytes - beforeBytes;
  const increment = admin.firestore.FieldValue.increment;

  // NOTE: `set(..., {merge:true})` only deep-merges *nested plain objects* —
  // dotted string keys like `'collections.classes.writes'` are stored as a
  // literal field name instead of a nested path (that shorthand only works
  // with `.update()`). So the per-collection breakdown below is built as a
  // real nested object, which `merge: true` does correctly merge in.
  const collectionUpdate = { storageBytes: increment(byteDelta) };

  const update = {
    lastWriteAt: admin.firestore.FieldValue.serverTimestamp(),
    firestoreStorageBytes: increment(byteDelta),
  };

  if (!before && after) {
    // Create
    update.writes = increment(1);
    update.docCount = increment(1);
    collectionUpdate.writes = increment(1);
    collectionUpdate.docCount = increment(1);
  } else if (before && after) {
    // Update
    update.writes = increment(1);
    collectionUpdate.writes = increment(1);
  } else if (before && !after) {
    // Delete
    update.deletes = increment(1);
    update.docCount = increment(-1);
    collectionUpdate.deletes = increment(1);
    collectionUpdate.docCount = increment(-1);
  }

  update.collections = { [collectionName]: collectionUpdate };

  await admin.firestore().collection('gymUsage').doc(gymId).set(update, { merge: true });
  return null;
}

GYM_SCOPED_COLLECTIONS.forEach((collectionName) => {
  exports[`trackUsage_${collectionName}`] = onDocumentWritten(
    `${collectionName}/{docId}`,
    (event) => recordGymUsage(collectionName, event),
  );
});

// ---------------------------------------------------------------------------
// Cloud Storage usage metering — product images are uploaded under
// `products/{gymId}/...` (see StorageService.uploadProductImage). Tracks
// storage bytes + file count per gym, folded into the cost estimate above.
// ---------------------------------------------------------------------------
function gymIdFromStoragePath(name) {
  const match = /^products\/([^/]+)\//.exec(name || '');
  return match ? match[1] : null;
}

exports.trackStorageUpload = onObjectFinalized({ region: 'us-east1' }, async (event) => {
  const gymId = gymIdFromStoragePath(event.data.name);
  if (!gymId) return null;
  const size = Number(event.data.size) || 0;
  await admin.firestore().collection('gymUsage').doc(gymId).set({
    cloudStorageBytes: admin.firestore.FieldValue.increment(size),
    cloudStorageFileCount: admin.firestore.FieldValue.increment(1),
    lastStorageWriteAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return null;
});

exports.trackStorageDelete = onObjectDeleted({ region: 'us-east1' }, async (event) => {
  const gymId = gymIdFromStoragePath(event.data.name);
  if (!gymId) return null;
  const size = Number(event.data.size) || 0;
  await admin.firestore().collection('gymUsage').doc(gymId).set({
    cloudStorageBytes: admin.firestore.FieldValue.increment(-size),
    cloudStorageFileCount: admin.firestore.FieldValue.increment(-1),
    lastStorageWriteAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return null;
});

// ---------------------------------------------------------------------------
// superAdminBackfillGymUsage — one-time (re-runnable) backfill that computes
// `gymUsage/{gymId}` from scratch by scanning every gym-scoped collection +
// the Storage bucket. Needed because the triggers above only observe writes
// going forward; existing data would otherwise be invisible to the usage
// screen until each document happens to be re-saved.
//
// Safe to re-run: it OVERWRITES (not increments) the scanned fields, so
// running it twice in a row gives the same result. `lastInvoiced*` fields
// (owned by invoice generation) are preserved.
// ---------------------------------------------------------------------------
exports.superAdminBackfillGymUsage = functions.https.onCall(
  { timeoutSeconds: 540, memory: '512MB' },
  async (data, context) => {
    await assertRole(context, 'super_admin');
    const db = admin.firestore();

    // gymId -> { writes, docCount, firestoreStorageBytes, collections }
    const usage = {};
    function bucket(gymId) {
      if (!usage[gymId]) {
        usage[gymId] = { docCount: 0, firestoreStorageBytes: 0, collections: {} };
      }
      return usage[gymId];
    }

    for (const col of GYM_SCOPED_COLLECTIONS) {
      const snap = await db.collection(col).get();
      for (const doc of snap.docs) {
        const d = doc.data();
        const gymId = d.gymId;
        if (!gymId) continue;
        const bytes = estimateDocBytes(d);
        const b = bucket(gymId);
        b.docCount += 1;
        b.firestoreStorageBytes += bytes;
        if (!b.collections[col]) b.collections[col] = { docCount: 0, storageBytes: 0 };
        b.collections[col].docCount += 1;
        b.collections[col].storageBytes += bytes;
      }
    }

    // Cloud Storage — product images live under products/{gymId}/...
    const [files] = await admin.storage().bucket().getFiles({ prefix: 'products/' });
    const storageByGym = {};
    for (const file of files) {
      const gymId = gymIdFromStoragePath(file.name);
      if (!gymId) continue;
      if (!storageByGym[gymId]) storageByGym[gymId] = { bytes: 0, count: 0 };
      storageByGym[gymId].bytes += Number(file.metadata.size) || 0;
      storageByGym[gymId].count += 1;
    }

    const gymIds = new Set([...Object.keys(usage), ...Object.keys(storageByGym)]);
    let backfilled = 0;
    for (const gymId of gymIds) {
      const u = usage[gymId] || { docCount: 0, firestoreStorageBytes: 0, collections: {} };
      const s = storageByGym[gymId] || { bytes: 0, count: 0 };
      await db.collection('gymUsage').doc(gymId).set({
        docCount: u.docCount,
        firestoreStorageBytes: u.firestoreStorageBytes,
        collections: u.collections,
        cloudStorageBytes: s.bytes,
        cloudStorageFileCount: s.count,
        writes: admin.firestore.FieldValue.increment(0),
        deletes: admin.firestore.FieldValue.increment(0),
        backfilledAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      backfilled += 1;
    }

    return { gymsBackfilled: backfilled };
  },
);
